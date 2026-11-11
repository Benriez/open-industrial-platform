#!/usr/bin/env python3
"""The bundle of a disposable instance for a foreign host is complete and safe.

The operator of the Raspberry Pi receives **one directory** and runs **one
command**. That is only acceptable if the bundle itself is proved: the
rehearsal assembles the bundle with **stubs** (so that the procedure is
measured without the artefacts of a foreign target), runs the whole
procedure — prepare, provision, start, mint the code of the operator
session, stop — and measures what it does and what it does not do.

What the rehearsal proves:
  * the bundle carries the Core, the simulation, the tool of the instance,
    the generator of the files of the instance, the scripts and the digest
    of every file;
  * the files of the instance are **absolute**, **inside** the instance and
    name the loopback of the host only;
  * the IPC configuration is in the **principal mode** — the mode in which
    the code of the operator session can be minted at all;
  * the procedure calls the Core with the paths of the instance and writes
    **nothing outside** the directory of the instance;
  * the bundle installs **no service**, publishes **no port** and names
    **no path of the machine it was built on**.

Usage:
  python3 tests/oip_pi_bundle.py [--evidence DIR]
"""
import argparse
import json
import os
import pathlib
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "oip_pi_bundle.sh"
GENERATOR = ROOT / "tools" / "oip_pi_instance.py"
CORE_SOURCE = ROOT / "crates" / "oip-server" / "src" / "main.rs"

# The stub of the Core and of the simulation. It records every call and
# behaves like the real binary where the procedure depends on it: the
# provisioning writes the data store, the daemon binds the loopback of the
# host and creates the socket of the local IPC, and the browser login prints
# a code.
STUB = '''#!/usr/bin/env python3
import json, os, pathlib, socket, sqlite3, sys, time

log = pathlib.Path(os.environ.get("OIP_STUB_LOG", "/tmp/oip-stub.log"))
arguments = sys.argv[1:]
with log.open("a") as handle:
    handle.write(json.dumps(arguments) + "\\n")

def the_value(flag):
    return arguments[arguments.index(flag) + 1] if flag in arguments else None

if "--browser-login" in arguments:
    print(json.dumps({"login_code": "0" * 64, "expires_in_seconds": 120}))
    raise SystemExit(0)

if "--provision" in arguments:
    config = json.loads(pathlib.Path(the_value("--config")).read_text())
    database = pathlib.Path(the_value("--database") or config["database"])
    database.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database)
    connection.execute("pragma user_version = 6")
    connection.commit()
    connection.close()
    print(json.dumps({"provisioned": str(database)}))
    raise SystemExit(0)

if "--daemon" in arguments:
    config = json.loads(pathlib.Path(the_value("--config")).read_text())
    port = int(config["http_port"])
    ipc = json.loads(pathlib.Path(the_value("--ipc-config")).read_text())
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(8)
    path = pathlib.Path(ipc["socket"])
    if path.exists():
        path.unlink()
    local = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    local.bind(str(path))
    local.listen(4)
    print(json.dumps({"status": "started", "port": port}), flush=True)
    while True:
        time.sleep(0.2)

# the simulation of the host
time.sleep(3600)
'''

# The words that would mean that the bundle installs a service or publishes a
# port. The README of the bundle may name the tunnel of the operator: it
# describes a step of the operator on the client, not something the bundle
# does.
FORBIDDEN_IN_SCRIPTS = ["systemctl", "launchctl", "crontab", "0.0.0.0",
                        "ssh ", "scp ", "curl "]


def free_port() -> int:
    """A port that is free on the machine of the rehearsal.

    The rehearsal does not use the port of the plan of the operator: a
    rehearsal that collides with a real instance is a rehearsal that
    measures the wrong thing.
    """
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def the_files(root: pathlib.Path) -> set:
    return {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()}


def run(command, cwd=None, env=None, timeout=120):
    environment = dict(os.environ)
    environment.update(env or {})
    return subprocess.run(command, cwd=cwd, env=environment, capture_output=True,
                          text=True, timeout=timeout)


def the_generator(directory: pathlib.Path, *arguments):
    return run([sys.executable, str(GENERATOR), "--instance", str(directory),
                *arguments])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-pi-bundle"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-pi-bundle-v1", "steps": [], "the_problems": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-pi-bundle-", dir="/private/tmp"))
    work.chmod(0o700)
    try:
        # ---------------------------------------------------- the stubs
        stubs = work / "stubs"
        stubs.mkdir()
        stub = stubs / "stub"
        stub.write_text(STUB)
        stub.chmod(0o755)
        (stubs / "oip-server").write_text(STUB)
        (stubs / "oip-simulated-server").write_text(STUB)
        (stubs / "oip-server").chmod(0o755)
        (stubs / "oip-simulated-server").chmod(0o755)

        # ---------------------------------------------------- the bundle
        bundle = work / "bundle"
        built = run(["sh", str(BUILDER), "aarch64-unknown-linux-gnu",
                     "--out", str(bundle), "--binaries", str(stubs)])
        assert built.returncode == 0, built.stderr
        names = sorted(the_files(bundle))
        report["the_files_of_the_bundle"] = names
        for expected in ["README.md", "MANIFEST.sha256", "bin/oip-server",
                         "bin/oip-simulated-server", "bin/start.sh",
                         "bin/stop.sh", "bin/status.sh", "bin/login-code.sh",
                         "tools/oip_ops.py", "tools/oip_pi_instance.py"]:
            assert expected in names, f"the bundle does not carry {expected}"
        report["steps"].append("the bundle carries the Core, the simulation, "
                                "the tool, the generator, the scripts and the manifest")

        # the manifest names the digest of every file of the bundle
        manifest = (bundle / "MANIFEST.sha256").read_text().strip().splitlines()
        assert len(manifest) == len(names) - 1, "the manifest does not name every file"
        for line in manifest:
            digest, name = line.split(None, 1)
            path = bundle / name.strip()
            actual = subprocess.run(["shasum", "-a", "256", str(path)],
                                    capture_output=True, text=True).stdout.split()[0]
            assert actual == digest, f"the digest of {name} does not match"
        report["steps"].append(f"the manifest names the digest of {len(manifest)} files")

        # ---------------------------------------------------- the safety of the bundle
        for path in bundle.rglob("*"):
            if path.is_file() and path.suffix in (".service", ".plist", ".timer"):
                report["the_problems"].append(f"the bundle carries a unit: {path}")
        for path in list((bundle / "bin").glob("*.sh")) + list((bundle / "tools").glob("*.py")):
            text = path.read_text()
            for word in FORBIDDEN_IN_SCRIPTS:
                if word in text:
                    report["the_problems"].append(
                        f"{path.name} contains {word!r}: the bundle must not install "
                        "a service, publish a port or reach another host")
            # A path of the machine it was built on: the bundle must run on a
            # host that has never seen this machine. The documentation of the
            # generator may name a home as an example; a script may not.
            machines = ["/Users/", "/private/tmp", "/Volumes/"]
            if path.suffix == ".sh":
                machines.append("/home/")
            for machine in machines:
                if machine in text:
                    report["the_problems"].append(
                        f"{path.name} names {machine!r}: the bundle must not name a "
                        "path of the machine it was built on")
        assert not report["the_problems"], report["the_problems"]
        report["steps"].append("the bundle installs no service, publishes no port and "
                                "names no path of the machine it was built on")

        # ---------------------------------------------------- the files of the instance
        instance = work / "instance"
        http_port = free_port()
        source_port = free_port()
        report["the_ports_of_the_rehearsal"] = {"the_core": http_port,
                                                 "the_source": source_port}
        prepared = the_generator(instance, "--http-port", str(http_port),
                                 "--source-port", str(source_port))
        assert prepared.returncode == 0, prepared.stderr
        summary = json.loads(prepared.stdout)
        report["the_preparation"] = summary
        core = json.loads((instance / "etc" / "core.json").read_text())
        plan = json.loads((instance / "etc" / "plan.json").read_text())
        ipc = json.loads((instance / "etc" / "ipc.json").read_text())
        report["the_core_configuration"] = core
        report["the_ipc_configuration"] = ipc
        assert core["database"] == str(instance / "state" / "oip-core.sqlite"), \
            "the data store is not the path of the instance"
        assert pathlib.Path(core["database"]).is_absolute()
        assert core["http_port"] > 0
        assert core["web_dir"] is None
        for source in core["sources"]:
            assert source["endpoint"].startswith("opc.tcp://127.0.0.1:"), \
                "a source of the instance is not on the loopback of the host"
            assert source["namespace"] == 2
            assert source["entity_id"], "the source of the instance names no entity"
        # The plan and the configuration name the same entity: the
        # provisioning of the Core refuses a source whose entity differs.
        assert {source["entity_id"] for source in core["sources"]} == \
            {source["entity_id"] for source in plan["sources"]}, \
            "the plan and the configuration name different entities"
        assert {source["id"] for source in core["sources"]} == \
            {source["source_id"] for source in plan["sources"]}, \
            "the plan and the configuration name different sources"
        assert ipc["socket"] == str(instance / "state" / "ipc.sock")
        assert "rest_policy" not in ipc, \
            "the IPC configuration is not in the principal mode"
        principals = {principal["id"] for principal in plan["principals"]}
        assert {client["policy"]["principal"] for client in ipc["clients"]} <= principals, \
            "a client of the IPC names a principal that the plan does not enable"
        for client in ipc["clients"]:
            assert client["uid"] == os.geteuid(), "the client does not name the local user"
            assert set(client["policy"]) == {"principal"}, \
                "a principal policy must not carry a legacy actor, grant or scope"
            assert pathlib.Path(client["credential_file"]).is_absolute()
            assert str(client["credential_file"]).startswith(str(instance))
        report["steps"].append("the files of the instance are absolute, inside the "
                                "instance and name the loopback of the host")

        # the refusals of the generator
        refusals = {}
        relative = run([sys.executable, str(GENERATOR), "--instance", "relative/path"])
        refusals["a_relative_directory"] = relative.returncode
        assert relative.returncode == 2 and "absolute" in relative.stderr
        personal = the_generator(pathlib.Path.home() / "Library" / "Application Support" / "OIP")
        refusals["the_personal_installation"] = personal.returncode
        assert personal.returncode == 2 and "personal installation" in personal.stderr
        again = the_generator(instance)
        refusals["an_already_prepared_instance"] = again.returncode
        assert again.returncode == 2 and "already prepared" in again.stderr
        report["the_refusals"] = refusals
        report["steps"].append("the generator refuses a relative directory, the personal "
                                "installation and an instance that is already prepared")

        # ---------------------------------------------------- the procedure
        calls = work / "calls.log"
        before = the_files(work)
        started = run(["sh", str(bundle / "bin" / "start.sh")],
                      env={"OIP_INSTANCE_DIR": str(instance),
                           "OIP_STUB_LOG": str(calls),
                           "OIP_HTTP_PORT": str(http_port),
                           "OIP_SOURCE_PORT": str(source_port)},
                      timeout=180)
        report["the_start"] = {"the_code": started.returncode,
                               "the_output": started.stdout[-800:],
                               "the_error": started.stderr[-400:]}
        assert started.returncode == 0, started.stderr
        recorded = [json.loads(line) for line in calls.read_text().splitlines() if line]
        report["the_calls_of_the_core"] = recorded
        provision = [call for call in recorded if "--provision" in call]
        daemon = [call for call in recorded if "--daemon" in call]
        assert provision and daemon, "the procedure did not provision and start the Core"
        assert str(instance / "etc" / "core.json") in provision[0], \
            "the provisioning did not use the configuration of the instance"
        assert str(instance / "etc" / "plan.json") in provision[0], \
            "the provisioning did not use the plan of the instance"
        assert str(instance / "state" / "oip-core.sqlite") in provision[0], \
            "the provisioning did not use the data store of the instance"
        assert str(instance / "etc" / "ipc.json") in daemon[0], \
            "the Core was started without the IPC configuration of the instance"
        assert "--database" in daemon[0] and \
            str(instance / "state" / "oip-core.sqlite") in daemon[0], \
            "the Core was started without the data store of the instance"
        assert any(call == ["--port", str(source_port)] for call in recorded), \
            "the simulation of the host was not started on its own port"
        credential = instance / "state" / "platform-reader.credential"
        assert credential.is_file(), "the credential of the operator was not written"
        mode = stat.S_IMODE(credential.stat().st_mode)
        assert mode == 0o600 and credential.stat().st_size == 32, \
            "the credential of the operator is not a protected file of 32 bytes"
        assert (instance / "state" / "ipc.sock").exists(), "the socket was not created"
        assert (instance / "state" / "oip.pid").is_file()
        after = the_files(work)
        outside = {name for name in after - before
                   if not name.startswith("instance/") and name != "calls.log"}
        assert not outside, f"the procedure wrote outside the instance: {outside}"
        report["the_files_written_outside_the_instance"] = sorted(outside)
        report["steps"].append("the procedure provisions, starts and writes nothing "
                                "outside the directory of the instance")

        # the code of the operator session
        minted = run(["sh", str(bundle / "bin" / "login-code.sh")],
                     env={"OIP_INSTANCE_DIR": str(instance),
                          "OIP_STUB_LOG": str(calls)}, timeout=60)
        report["the_code_of_the_session"] = {"the_code": minted.returncode,
                                             "the_output": minted.stdout[-200:]}
        assert minted.returncode == 0, minted.stderr
        assert "login_code" in minted.stdout, "no code was minted"
        recorded = [json.loads(line) for line in calls.read_text().splitlines() if line]
        login = [call for call in recorded if "--browser-login" in call]
        assert login, "the code was not minted over the local IPC"
        assert str(instance / "state" / "ipc.sock") in login[0]
        assert str(credential) in login[0], \
            "the code was not minted with the credential of the operator"
        report["steps"].append("the code of the operator session is minted over the "
                                "local IPC of the instance")

        # the stop
        stopped = run(["sh", str(bundle / "bin" / "stop.sh")],
                      env={"OIP_INSTANCE_DIR": str(instance),
                           "OIP_STUB_LOG": str(calls)}, timeout=120)
        report["the_stop"] = {"the_code": stopped.returncode,
                              "the_output": stopped.stdout[-400:]}
        assert stopped.returncode == 0, stopped.stderr
        assert not (instance / "state" / "oip.pid").exists(), \
            "the Core was not stopped"
        report["steps"].append("the instance stops without a signal that is forced")

        # ---------------------------------------------------- the Core binds the loopback
        source = CORE_SOURCE.read_text()
        assert "Ipv4Addr::LOCALHOST" in source, \
            "the Core does not bind the loopback of the host"
        assert "Ipv4Addr::UNSPECIFIED" not in source, \
            "the Core binds a port of every interface of the host"
        report["the_core_binds_the_loopback"] = True
        report["steps"].append("the Core binds the loopback of the host: the tunnel of "
                                "the operator is the only way in")

        # the ports of the instance are free on the machine of the rehearsal
        with socket.socket() as probe:
            probe.settimeout(0.4)
            assert probe.connect_ex(("127.0.0.1", http_port)) != 0, \
                "the port of the instance is still open after the stop"
    except Exception as error:  # a failed rehearsal is a receipt as well
        report["the_problems"].append(f"{type(error).__name__}: {error}")
        report["status"] = "FAIL"
    finally:
        # The rehearsal owns the processes it started: they are stopped
        # before the directory of the rehearsal is removed.
        for name in ("oip.pid", "simulator.pid"):
            path = work / "instance" / "state" / name
            if path.is_file():
                try:
                    os.kill(int(path.read_text().strip()), 15)
                except (OSError, ValueError):
                    pass
        shutil.rmtree(work, ignore_errors=True)

    report["status"] = "FAIL" if report["the_problems"] else "PASS"
    report["the_revision"] = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    report["the_tree"] = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["the_working_tree_is_clean"] = not subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "pi-bundle.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["status"],
                      "the_steps": len(report["steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
