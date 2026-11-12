# The App Store Connect metadata of the OIP client

The values below are the **prepared** answers of the listing. The operator enters them in
App Store Connect; the two URLs and the answers that are personal stay the operator's.

| Field | Value | Note |
|---|---|---|
| App name (≤ 30 characters) | `Open Industrial Platform` | 24 characters |
| Subtitle (≤ 30 characters) | `Operations Workstation` | 22 characters |
| Bundle identifier | `org.openindustrial.oipDashboard` | the identifier of the release build |
| Category | Utilities | the Mac App Store category `public.app-category.utilities` |
| Primary language | English (U.S.) | the texts of the listing are written in English; the **client itself** shows German texts, because it has **no** localisation framework. A second language would need a translation of the surface — the operator's decision |
| Copyright | `© 2026 Open Industrial Platform` | the operator confirms the holder; the bundle carries the same holder (`NSHumanReadableCopyright`) |
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
| Secondary category | **the operator's choice** | the primary category is Utilities |
| Pricing and availability | **the operator's decision** | the price and the territories |
| Licensing / EULA | **the operator's decision** | the terms of the use |
| Localised metadata | **absent**: one English set of texts, while the screenshots of the listing are German | a second language needs a translation of the surface |
| What's New | **absent**: the first version has no notes of a version | |

## The fields that the operator fills in App Store Connect

The listing is **prepared**; the fields below are **not** prepared because they are the operator's
decision or the operator's identity. The table names every one of them, so that nothing is
forgotten at the upload:

| Field | Why it is the operator's |
|---|---|
| Support URL, Marketing URL, Privacy policy URL | the URLs of the operator; the privacy policy itself is prepared (`privacy-policy.md`) |
| The contact of the privacy policy | the address of the operator (`privacy-policy.md`) |
| The age-rating questionnaire | the answers of the operator |
| The app privacy details | the operator confirms the prepared answer |
| The export-compliance answer | the operator confirms it in App Store Connect |
| Secondary category, pricing, availability, licensing | the decision of the operator |
| The localised metadata | a translation of the surface is the operator's decision |
| The App Review information | see below: the client has **no** account, and the access of the reviewer is the operator's |
| The Apple identity (team, profile, certificate) | the identity of the operator; the recipe names the placeholders (`ExportOptions.plist.template`) |
| The upload itself | the action of the operator |

## The App Review information

The client has **no account and no password**: it asks for a **one-time code** that the Core of
OIP mints for the operator on the instance itself. The reviewer therefore needs a **running
instance** of the Core on the machine of the review — the notes below tell the reviewer exactly
what to do, and the operator decides how the reviewer gets that instance.

**Notes for the reviewer (proposed):**

> OIP is a read-only operations workstation for industrial infrastructure. It shows the devices,
> the services, the measurements and the diagnostics that a **local Core** of OIP collects; it
> never writes to a device and it never sends data off the machine.
>
> * **The Core runs on the machine of the reviewer.** It is a local server that answers on the
>   loopback (`127.0.0.1`) — the client is configured for that address. The Core is started by
>   the operator of the instance; the commands are in the operations runbook of the project.
> * **The sign-in is a one-time code, not a password.** The Core mints a one-time code for the
>   operator on the instance itself (a local IPC call, not a remote service). The client asks
>   for the code, the code is used once, and the session ends with the instance. There is no
>   account, no password and no reset — the app has **no** remote identity of its own.
> * **The Core needs data to show.** The measurements come from the OPC-UA simulation that
>   ships with the Core, so the reviewer sees a full, honest surface without any plant.
> * **No data is collected.** The privacy manifest of the bundle declares "Data Not Collected";
>   the client talks to the Core over the loopback of the machine only.

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
