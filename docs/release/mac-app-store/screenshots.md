# The store assets of the Mac App Store listing

The listing of the client needs the **screenshots** of the app. This file records what Apple
accepts, where the requirement was read, and which captures this release delivers.

## The requirement (official source, read on 2026-11-11)

* **Screenshot specifications** — App Store Connect Help, "Reference → App information":
  <https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/>.
* For a **Mac** app the screenshot size is **one of the following, with a 16:10 aspect ratio**:
  * 1280 x 800 pixels
  * 1440 x 900 pixels
  * 2560 x 1600 pixels
  * 2880 x 1800 pixels
  * The screenshots are **required for Mac apps**.
* **Manage your App Store assets** — App Store Connect Help:
  <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets/>.
  The assets are uploaded through the Asset Library or the Product Page Information of the
  version; the guidelines of App Review (2.3.3 and 2.3.4) apply to them.
* **Creative assets specifications** — App Store Connect Help: **"Images can't include alpha
  channels or transparencies."**

The requirement of the icon (1024 x 1024) and of the screenshots was previously cited from the
submitting page of Apple, which names **no pixel sizes**; the sizes are cited from the
specification above now.

## The assets of this release

| Asset | Size | Workstation |
|---|---|---|
| `store-overview-1440x900.png` | 1440 x 900 | Übersicht (Operations Workstation) |
| `store-devices-1440x900.png` | 1440 x 900 | Geräte & Dienste |
| `store-network-1440x900.png` | 1440 x 900 | Netzwerk & VPN |
| `store-opcua-1440x900.png` | 1440 x 900 | OPC-UA-Browser |
| `store-diagnostics-1440x900.png` | 1440 x 900 | Diagnose & Ereignisse |
| `store-settings-1440x900.png` | 1440 x 900 | Einstellungen |

The captures are **measured**, not asserted
(`tests/oip_store_screenshots.py`, `docs/evidence/oip-store-screenshots/store-screenshots.json`):

* every capture has **exactly** 1440 x 900 pixels — the size is read out of the header of the
  file itself, and 1440 x 900 is one of the four sizes that Apple accepts;
* every capture carries **no alpha channel** — the colour type of the PNG is read out of the
  header as well (type 2, truecolour, without an alpha channel);
* every capture is the **viewport** of the client — never the full page, whose height would be
  whatever the content happens to be;
* the captures show the **approved Spectrum-2027 shell** and carry **none** of the prohibited
  regressions R1-R10 of `docs/design/OIP_CANONICAL_UI_BASELINE.md` — the rehearsal checks every
  marker of the contract on every workstation, with the same exemptions that the canonical gate
  applies (the agent-first principle is named in the technical context of the Settings
  workstation);
* the captures are taken against a **managed Core of the release** whose source is the local
  OPC-UA simulation of the release — the same source that the instance on the Raspberry Pi
  collects. The surface states the origin of the data ("Ursprung: Simulation", the badge
  "DEMO / SIMULATION"); the listing therefore does not pretend that the data of a demo is the
  data of a plant.

## What is **not** done here

* The **acceptance of the visible result by the operator** is still pending (G12). A capture is
  a measurement of the surface, never an acceptance of it.
* The listing with the **own infrastructure of the operator** is the operator's decision: the
  captures of this release show the managed Core, and the data of a real installation is the
  operator's to publish.
* The **upload** itself is the operator's action, together with the identity, the certificate,
  the profile and the two public URLs (`docs/release/mac-app-store/requirements.md`).
