# The App Store Connect metadata of the OIP client

The values below are the **prepared** answers of the listing. The operator enters them in
App Store Connect; the two URLs and the answers that are personal stay the operator's.

| Field | Value | Note |
|---|---|---|
| App name (≤ 30 characters) | `Open Industrial Platform` | 24 characters |
| Subtitle (≤ 30 characters) | `Operations Workstation` | 22 characters |
| Bundle identifier | `org.openindustrial.oipDashboard` | the identifier of the release build |
| Category | Utilities | the Mac App Store category `public.app-category.utilities` |
| Primary language | English (U.S.) / German (Deutschland) | the client is localised in both |
| Copyright | `© 2026 Open Industrial Platform` | the operator confirms the holder |
| Version | the `CFBundleShortVersionString` of the release build | the manifest of the release names it |
| Build | the `CFBundleVersion` of the release build | the manifest of the release names it |
| Minimum macOS | the deployment target of the release build | the manifest of the release names it |
| Support URL | **the operator's URL** | required on the product page |
| Marketing URL | **the operator's URL** | optional |
| Privacy policy URL | **the operator's URL** | required; the text is `privacy-policy.md` |
| Age rating | the answers of the operator; the app carries no user content, no advertising, no gambling, no unrestricted web access, no user-generated content, and no medical or financial data | the updated questions of 2026-01-31 |
| App privacy details | **Data Not Collected** — the client transmits nothing off the device; it talks to the Core of OIP on the loopback of the machine | <https://developer.apple.com/app-store/app-privacy-details/> |
| Encryption export compliance | the app uses the system TLS stack of the operating system; it exports no cryptography of its own — the operator confirms the answer in App Store Connect | the standard answer |
| Advertising | no | |
| In-app purchases | none | |
| Age rating notes | the app shows the state of industrial devices of the operator; it never collects user content | |

## The description of the listing

> OIP is the operations workstation for industrial infrastructure. It shows the devices,
> the services, the measurements and the diagnostics of the infrastructures that the Core
> of OIP collects — over the loopback of the machine or over a forward to a Core on
> another host.
>
> * **Overview** — the state of the authorized infrastructures at a glance.
> * **Devices & Services** — the devices of the infrastructure with their live values,
>   their reachability and their health.
> * **Network & VPN** — the network state that the Core knows; the absences are named,
>   not filled.
> * **OPC-UA Browser** — the address space of an OPC-UA server as the server delivers
>   it, read without measuring.
> * **Diagnostics & Events** — the persisted evidence of the Core: documented gaps,
>   health transitions and the diagnosis history.
> * **Settings** — the settings of the instance, offline where the Core demands it.
>
> The client never writes to a device. Every value it shows comes from the Core of OIP,
> and every value it cannot obtain is named as missing — never as zero.

## The keywords (100 characters)

`industrial,iot,operations,monitoring,diagnostics,opc-ua,devices,workstation,infrastructure`

## The promotional text

> The operations workstation for the industrial infrastructure of your own Core: devices,
> services, measurements and diagnostics — with every missing value named as missing.
