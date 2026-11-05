use crate::contracts::{Device, Health, Incident, Link};

pub const SCENARIOS: &[&str] = &[
    "normal",
    "gpu",
    "inference",
    "vpn",
    "sensor",
    "agent",
    "offline",
];

pub fn devices(scenario: &str, opcua: &str) -> Vec<Device> {
    let inventory = [
        ("evo", "AMD EVO-X2", "Compute", "LAN", "Ethernet"),
        ("pi3", "Raspberry Pi 3B", "Edge", "LAN", "Ethernet"),
        ("pi4", "Raspberry Pi 4", "Edge", "LAN", "Ethernet"),
        ("windows", "Windows-PC", "Desktop", "LAN", "Ethernet"),
        ("mac", "macOS-Laptop", "Laptop", "LAN", "Wi-Fi"),
        ("mini", "Linux-Mini-PC", "Compute", "LAN", "Ethernet"),
        ("tablet", "Android-Tablet", "Mobile", "LAN", "Wi-Fi"),
        ("phone", "Android-Smartphone", "Mobile", "LAN", "Wi-Fi"),
        ("esp32", "ESP32", "Sensor", "LAN", "Wi-Fi"),
        ("router", "OpenWrt-Router", "Gateway", "LAN", "Ethernet"),
        ("cast", "Chromecast", "Media", "LAN", "Wi-Fi"),
        ("tv", "Smart-TV", "Media", "LAN", "Wi-Fi"),
        ("hue", "Philips Hue", "Bridge", "LAN", "Ethernet"),
        (
            "remote-linux",
            "Remote-Linux-Server",
            "Server",
            "Tailnet",
            "Tailnet",
        ),
        (
            "remote-windows",
            "Remote-Windows-Server",
            "Server",
            "Remote Site",
            "WireGuard",
        ),
        ("rdp", "RDP-Server", "Service", "Remote Site", "WireGuard"),
        (
            "M-01",
            "OPC-UA-Sensoren · M-01",
            "Industrial",
            "LAN",
            "OPC UA",
        ),
    ];
    inventory
        .into_iter()
        .map(|(id, name, kind, location, connection)| {
            let industrial = id == "M-01";
            let remote = location != "LAN";
            Device {
                data_source_id: None,
                is_faulted: false,
                id: id.into(),
                name: name.into(),
                kind: kind.into(),
                location: location.into(),
                connection: connection.into(),
                simulated: true,
                health: Health {
                    reachability: if industrial {
                        if opcua == "connected" {
                            "reachable"
                        } else {
                            "unknown"
                        }
                    } else {
                        "reachable"
                    }
                    .into(),
                    vpn_transport: if !remote {
                        "not_applicable"
                    } else if scenario == "vpn" {
                        "degraded"
                    } else {
                        "connected"
                    }
                    .into(),
                    agent_availability: if id == "remote-linux" && scenario == "agent" {
                        "unavailable"
                    } else {
                        "unknown"
                    }
                    .into(),
                    service_health: if industrial { opcua } else { "unknown" }.into(),
                    telemetry_freshness: if industrial && opcua == "connected" {
                        "fresh"
                    } else {
                        "unknown"
                    }
                    .into(),
                },
            }
        })
        .collect()
}

pub fn topology(scenario: &str) -> Vec<Link> {
    [
        ("router", "evo", "LAN", 1.4),
        ("router", "M-01", "LAN", 2.8),
        ("router", "remote-linux", "Tailnet", 36.0),
        ("router", "remote-windows", "WireGuard", 61.0),
        ("remote-windows", "rdp", "Site VPN", 3.0),
    ]
    .into_iter()
    .map(|(from, to, transport, latency)| {
        let degraded = scenario == "vpn" && to == "remote-linux";
        Link {
            from: from.into(),
            to: to.into(),
            transport: transport.into(),
            latency_ms: Some(if degraded { 287.0 } else { latency }),
            packet_loss_percent: Some(if degraded { 17.8 } else { 0.2 }),
            status: if degraded { "degraded" } else { "connected" }.into(),
            simulated: true,
        }
    })
    .collect()
}

pub fn incidents(scenario: &str) -> Vec<Incident> {
    let (title, category, device, supporting, contradicting, missing) = match scenario {
        "gpu" => ("Hohe GPU-Auslastung", "Resources", "evo", "Demo: GPU 97 % bei unveränderter Arbeitslast", "Demo: Netzwerkpfad bleibt stabil", "GPU-Exporter und reale Prozessmetriken"),
        "inference" => ("Langsame lokale Inferenz", "Application", "evo", "Demo: Inferenz p95 steigt von 0,83 auf 4,8 s", "Demo: kein erhöhter Paketverlust", "Batchgröße, Tokenrate und Profiler-Messungen"),
        "vpn" => ("Instabile VPN-Verbindung", "Network", "remote-linux", "Demo: RTT 287 ms, Paketverlust 17,8 %", "Demo: LAN-Latenz bleibt stabil", "Unabhängige Pfad- und Relay-Messungen"),
        "sensor" => ("OPC-UA-Sensoralarm", "Industrial", "M-01", "Szenario critical_sensor im lokalen OPC-UA-Simulator angefordert; aktuellen Temperaturwert und alarm_active separat prüfen", "Eine Kommunikationsstörung ist damit nicht nachgewiesen", "Unabhängige physische Referenzmessung"),
        "agent" => ("VPN erreichbar · Agent nicht verfügbar", "Agent", "remote-linux", "Demo: VPN erreichbar, Agent-Heartbeat fehlt", "Demo: VPN-Transport antwortet", "Service-Health und Agent-Protokoll"),
        "offline" => ("Collector-Verbindung unterbrochen", "Collection", "M-01", "Lokaler Simulationsserver wird sechs Sekunden gestoppt", "Host-Telemetrie liegt nicht vor", "Neue OPC-UA-Observation nach Wiederanlauf"),
        _ => return Vec::new(),
    };
    vec![Incident {
        id: format!("demo-{scenario}"),
        title: title.into(),
        category: category.into(),
        device_id: device.into(),
        simulated: true,
        supporting: vec![supporting.into()],
        contradicting: vec![contradicting.into()],
        missing: vec![missing.into()],
        timeline: vec![
            "T+0 · Deterministisches Demoszenario gewählt".into(),
            "T+1 · Beobachtungen vergleichen".into(),
            "T+2 · Hypothese offen: Kausalität nicht belegt".into(),
        ],
    }]
}
