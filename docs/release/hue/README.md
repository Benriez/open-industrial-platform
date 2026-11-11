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

The capabilities of the bridge that this pin makes possible are **read-only**: the public
configuration of the bridge. The lights, the groups and the scenes need an application token,
and the creation of a token is a **write on the device** that belongs to the operator.
