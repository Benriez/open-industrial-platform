# The pin of the Philips Hue Bridge

The Hue Bridge of the operator serves HTTPS with a certificate that it issued itself: the
certificate is signed by a *root* of the bridge that the bridge does not present, so the chain
of the bridge is **incomplete** and no ordinary trust store can verify it. The identity of the
bridge can therefore only be verified by **pinning** its own certificate — exactly the way the
SSH onboarding pins the host key of a host.

`bridge-certificate.pem` is that pin: the public certificate of the bridge
(`CN=001788FFFE48E917`, issued by `CN=root-bridge`, valid until 2038-01-19), measured on
2026-11-11 from the bridge of the operator at `192.168.1.131` with

```sh
python3 tools/oip_hue.py --host 192.168.1.131 --measure --out docs/release/hue/bridge-certificate.pem
```

* **SHA-256 fingerprint:** `95:D7:5C:4C:57:03:71:C1:1D:71:7E:25:BE:3C:16:2D:7B:EA:44:74:22:20:AB:2C:27:B9:3F:F8:44:C8:6E:3A`
* **SHA-256 of the file:** `39abc2d119d41f0bd27dab5d73bf7cb1d1b1f679111f3779a0cc2dd818bf3857`

The pin is **public material** — it is the certificate of the device, not a secret. A bridge
that presents another certificate is **refused**: the read of the bridge is verified against
the pin, and the refusal is measured
(`tests/oip_hue_device.py`, `docs/evidence/oip-hue-device/hue-device.json`).

## Collector setup

Configure a `hue.profiles` entry in the Core instance configuration. Use the
registered device ID, an authorized principal, the bridge IP, port 443 and an
absolute `pin_file` path. The collector selects an OpenSSL client that supports
`-partial_chain` and `-verifyCAfile` at startup. An incompatible installation
reports `HUE_TLS_TOOL_UNAVAILABLE`.

The public identity is readable with the pin. To read lights, pair a Hue
application using the bridge's link button, save the issued username in a
private mode-0600 file and set `token_file` to its absolute path. The collector
uses GET requests. It reports the light count and on/off count across the
bridge, with individual names, states and available brightness for resource
IDs 1 through 32. The smart plug reports on/off state.

`tests/oip_hue_device.py` accepts an optional `--token-file`. Run both modes
to verify authenticated readings, cross-organization access and rejection of
a different certificate. The deployed result is recorded in
`docs/evidence/oip-hue-device/collector.json`.

In Devices & Services, open Philips Hue Bridge and expand Engineering, then
Observation & Telemetry. The separate SSH setup panel can display
`Telemetry NoCollector` when the bridge has active Hue readings.


## Dashboard control

Overview and Dashboard list every light returned by a paired bridge, including
resource IDs above 32. The telemetry catalogue limit applies only to stored
measurements. Switching, brightness, hue/saturation and white temperature are
available according to each resource's reported capabilities.

A bridge profile defaults to monitoring only. Set `control_enabled` to
`true` to enable commands for the profile's listed principals. Each command
requires device, telemetry and inventory management rights on that source.
Reader accounts see the live state. Browser commands use session and CSRF
protection. The Core checks the pinned bridge, the addressed light's current
capabilities and each acknowledgement before reporting acceptance.
