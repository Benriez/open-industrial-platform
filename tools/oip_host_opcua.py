#!/usr/bin/env python3
"""Loopback OPC-UA view of live Linux host measurements for OIP."""

import asyncio
import os
import socket
import time
from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path

from asyncua import Server, ua
from asyncua.common.callback import CallbackType


def cpu_ticks():
    fields = Path("/proc/stat").read_text().splitlines()[0].split()[1:]
    values = [int(value) for value in fields]
    return sum(values), values[3] + (values[4] if len(values) > 4 else 0)


def memory_values():
    values = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, rest = line.split(":", 1)
        values[key] = int(rest.strip().split()[0]) * 1024
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", total)
    used = max(0, total - available)
    return total, used, 0.0 if total == 0 else used * 100.0 / total


def sensor_metrics():
    found = {"cpu_temperature_c": [], "soc_temperature_c": [], "gpu_temperature_c": []}
    for path in Path("/sys/class/thermal").glob("thermal_zone*/temp"):
        try:
            temperature = int(path.read_text().strip()) / 1000.0
            zone = path.parent
            kind = (zone / "type").read_text().strip().lower()
            if "gpu" in kind:
                found["gpu_temperature_c"].append(temperature)
            elif "soc" in kind or "cpu-thermal" in kind:
                found["soc_temperature_c"].append(temperature)
            elif "cpu" in kind or "thermal" in kind:
                found["cpu_temperature_c"].append(temperature)
        except (OSError, ValueError):
            pass
    gpu_utilization = None
    gpu_model = None
    for hwmon in Path("/sys/class/hwmon").glob("hwmon*"):
        try:
            name = (hwmon / "name").read_text().strip().lower()
        except OSError:
            name = ""
        category = "gpu_temperature_c" if any(v in name for v in ("amdgpu", "nvidia", "gpu")) else (
            "cpu_temperature_c" if any(v in name for v in ("cpu", "k10temp", "coretemp", "zenpower")) else None
        )
        if category:
            for path in hwmon.glob("temp*_input"):
                try:
                    found[category].append(int(path.read_text().strip()) / 1000.0)
                except (OSError, ValueError):
                    pass
        if category == "gpu_temperature_c":
            try:
                gpu_model = name
            except OSError:
                pass
            for path in hwmon.glob("gpu_busy_percent"):
                try:
                    gpu_utilization = float(path.read_text().strip())
                except (OSError, ValueError):
                    pass
    result = {key: max(values) for key, values in found.items() if values}
    if not gpu_model:
        for path in Path("/sys/class/drm").glob("card*/device/uevent"):
            try:
                fields = dict(line.split("=", 1) for line in path.read_text().splitlines() if "=" in line)
                driver = fields.get("DRIVER", "")
                if driver:
                    gpu_model = "Broadcom V3D" if driver == "v3d" else driver
                    break
            except OSError:
                pass
    if gpu_utilization is not None:
        result["gpu_utilization_percent"] = gpu_utilization
    if gpu_model:
        result["gpu_model"] = gpu_model
    return result


async def main():
    port = int(os.environ.get("OIP_OPCUA_PORT", "4840"))
    server = Server()
    await server.init()
    server.set_endpoint(f"opc.tcp://127.0.0.1:{port}/oip/")
    server.set_server_name(f"OIP live host service · {socket.gethostname()}")
    namespace = await server.register_namespace("urn:oip:live-host")
    root = await server.nodes.objects.add_folder(namespace, "OIP")
    host = await root.add_folder(namespace, "host")
    operator = await root.add_folder(namespace, "operator")

    async def variable(parent, path, value, writable=False):
        name = path.rsplit(".", 1)[-1]
        node = await parent.add_variable(
            ua.NodeId(path, namespace), name, value
        )
        if writable:
            await node.set_writable()
        else:
            await node.set_read_only()
        return node

    cpu = await variable(host, "host.cpu_utilization_percent", 0.0)
    mem_total = await variable(host, "host.memory_total_bytes", 0)
    mem_used = await variable(host, "host.memory_used_bytes", 0)
    mem_percent = await variable(host, "host.memory_used_percent", 0.0)
    uptime = await variable(host, "host.uptime_seconds", 0.0)
    initial_sensors = sensor_metrics()
    sensor_nodes = {}
    for name in ("cpu_temperature_c", "soc_temperature_c", "gpu_temperature_c", "gpu_utilization_percent", "gpu_model"):
        if name in initial_sensors:
            sensor_nodes[name] = await variable(host, f"host.{name}", initial_sensors[name])
    await variable(host, "host.hostname", socket.gethostname())
    await variable(host, "host.os", Path("/etc/os-release").read_text().splitlines()[0])

    # These two bounded operator properties are deliberately writable. Host
    # measurements above remain read-only at the OPC-UA server itself.
    maintenance = await variable(operator, "operator.maintenance", False, writable=True)
    note = await variable(operator, "operator.note", "", writable=True)
    operator_nodes = {maintenance.nodeid, note.nodeid}

    def stamp_operator_write(event, _service):
        if not event.is_external:
            return
        writes = event.request_params.NodesToWrite
        for index, write in enumerate(writes):
            if write.NodeId in operator_nodes and write.AttributeId == ua.AttributeIds.Value:
                # The service owns these variables. Timestamp the value at the
                # host so an ordinary OPC-UA write can be read back by OIP.
                value = replace(
                    write.Value, SourceTimestamp=datetime.now(timezone.utc), SourcePicoseconds=None
                )
                writes[index] = replace(write, Value=value)

    server.subscribe_server_callback(CallbackType.PreWrite, stamp_operator_write)

    started = time.monotonic()
    previous_total, previous_idle = cpu_ticks()
    async with server:
        while True:
            await asyncio.sleep(2)
            current_total, current_idle = cpu_ticks()
            total_delta = max(1, current_total - previous_total)
            idle_delta = max(0, current_idle - previous_idle)
            previous_total, previous_idle = current_total, current_idle
            total, used, percent = memory_values()
            sensors = sensor_metrics()
            await cpu.write_value(max(0.0, min(100.0, 100.0 * (1 - idle_delta / total_delta))))
            await mem_total.write_value(total)
            await mem_used.write_value(used)
            await mem_percent.write_value(percent)
            await uptime.write_value(time.monotonic() - started)
            for name, node in sensor_nodes.items():
                if name in sensors:
                    await node.write_value(sensors[name])
            # Read back to keep the writable properties in the active address
            # space and make external changes immediately visible to clients.
            await maintenance.read_value()
            await note.read_value()


if __name__ == "__main__":
    asyncio.run(main())
