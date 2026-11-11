# The Mac App Store readiness of the OIP client (the checklist of the official requirements)

The requirements were read on **2026-11-11** from the official sources of Apple. Every
row names its source. A row that is not **MET** is not a claim: it is either a piece of
work that the loop delivers or an **operator action** (the identity of the developer, the
certificate, the account). Nothing here is the permission to submit or to publish.

## The current official requirements

| # | Requirement | Source (read 2026-11-11) | State of OIP | What closes it |
|---|---|---|---|---|
| R1 | The apps uploaded to App Store Connect must be built with **Xcode 26** or later (since 2026-04-28) | <https://developer.apple.com/news/upcoming-requirements/> (`SDK minimum requirements`) | **MET** — the machine of the release builds with Xcode 26.6 | — |
| R2 | The app must declare the **approved reasons for the required-reason APIs** it uses (since 2024-05-01) | <https://developer.apple.com/news/upcoming-requirements/> (`Approved reasons for APIs`), <https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk> | **MET** — the bundle carries `PrivacyInfo.xcprivacy` and the packaging check reads it | — |
| R3 | The macOS apps uploaded to App Store Connect must **not** carry the extended attribute `com.apple.quarantine` on any file (since 2025-02-18) | <https://developer.apple.com/news/upcoming-requirements/> (`Quarantine attribute in macOS apps`) | **MET** — the packaging check reads the attribute of **every** file of the bundle and the release bundle carries none | — |
| R4 | The **hardened runtime** must be enabled for the app and the command line targets | <https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution> (`Prepare your software for notarization`) — the same protection the App Store submission checks; the direct distribution of G9/N17 needs it in any case | **OPEN** — the **archive** of the distribution carries the hardened runtime (`tools/oip_mas_package.py` measures the flag in the signature), but the **Xcode project** does not set it: the local bundle is signed ad-hoc and the library validation of the hardened runtime refuses an ad-hoc framework, so the local bundle would stop launching. The measurement of that refusal is in the receipt of the packaging (`the_launch_of_the_hardened_bundle`) | a **distribution-only** build configuration of the Xcode project — the local bundle keeps the ad-hoc signature, the archive carries the hardened runtime with the identity of the operator |
| R5 | The Mac App Store requires the **app sandbox** | the App Store submission (the equivalent security checks of the store) | **MET** — `com.apple.security.app-sandbox` is in `Runner/Release.entitlements` | — |
| R6 | The entitlements of the notarisation must be **XML and ASCII**, the code signing must cover **every executable**, with a **secure timestamp**, and **no** `com.apple.security.get-task-allow` | <https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution> | **PARTIAL** — the packaging check reads the signature of **every executable** of the bundle and asserts the forbidden entitlements; the **secure timestamp** is a property of the signature with the identity of the operator and is therefore **OPERATOR** | the operator's signed archive |
| R7 | The **privacy policy URL** and a **support URL** are required on the product page | <https://developer.apple.com/app-store/app-privacy-details/> (`Privacy links`), <https://developer.apple.com/distribute/app-review/> | **OPEN** — the texts exist in this directory; the **public URLs** are the operator's | the operator publishes the two URLs |
| R8 | The **app privacy details** must state every data type that the app collects | <https://developer.apple.com/app-store/app-privacy-details/> | **OPEN** — the answers are prepared (`metadata.md`): the client collects **nothing** off the device | the answers of the operator in App Store Connect |
| R9 | The **icon** of the app (1024×1024) and the **screenshots** of the app in the required sizes | the sizes: App Store Connect Help, [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) (read 2026-11-11); the assets: [Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets/) | **MET** — the screenshots of the six workstations in **1440 x 900** (one of the four sizes that Apple accepts for a Mac app, 16:10, **no alpha channel**) are measured in `docs/evidence/oip-store-screenshots/`; the packaging check reads every file of the listing | — |
| R10 | The **signing** of the upload uses the *Mac App Distribution* profile and the *Apple Distribution* certificate of the developer | <https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution> (the certificate types: for the store the *Apple Distribution*, for the direct distribution the *Developer ID*) | **OPERATOR** — the identity, the certificate and the profile belong to the operator | the operator's archive |
| R11 | The **notarisation** uses `notarytool` (not `altool`, since 2023-11-01) and the ticket is stapled | <https://developer.apple.com/news/upcoming-requirements/> (`Apple notary service update`) | **N/A for the store** — the App Store submission already includes the equivalent checks; `notarytool` is the path of the **direct** distribution (G9/N17) | the runbook of the direct distribution |
| R12 | The **age rating** uses the updated questions (since 2026-01-31) | <https://developer.apple.com/news/upcoming-requirements/> (`Age Rating Updates`) | **OPEN** — the answers are prepared (no objectionable content, no user content) | the answers of the operator |
| R13 | The **trader status** is required for the EU | <https://developer.apple.com/news/upcoming-requirements/> (`DSA trader status`) | **OPERATOR** — it belongs to the developer account | the operator's account |
| R14 | The **export** of the archive for the store uses `xcodebuild -exportArchive` with an options file; the upload of the product is a separate step | `xcodebuild -help` (the `-exportArchive` form of the toolchain of the machine, Xcode 26.6) | **MET** — the recipe exists and is measured: `docs/release/mac-app-store/ExportOptions.plist.template` (every identity of the operator is a **placeholder**) and `tools/oip_mas_export.py` (it invents no credential, it renders the options into `target/` and it prints the command; the export and the upload are the operator's action) | — |
| R15 | The App Review needs **access to the app** — a demo account when the app requires a sign-in | App Store Connect Help, *Platform version information* → *App Review information* (external knowledge, read 2026-11-11) | **PARTIAL** — the client has **no account**: it asks for a **one-time code** that the Core mints on the instance. The **notes for the reviewer** are prepared (`metadata.md`); the **instance for the reviewer** is the operator's | the operator provides the instance for the reviewer |

## What the app does and does not do (the disclosure of the privacy details)

The client of OIP is a **presentation client**: it shows the state that the **Core** of OIP
delivers. It talks to the Core over the loopback of the machine (or over a forward of the
loopback to a Core on another host). It **collects no data off the device**: the session
cookie lives in the memory of the process, there is no analytics, no advertising, no
crash reporter of a third party, and no transmission of anything to a server of the
developer. The answer of the app privacy details is therefore **"Data Not Collected"**, and
the privacy manifest declares **no tracking** and **no collected data type**.

The only network entitlement of the release build is `com.apple.security.network.client`:
the client reaches the Core. It is not a server and it does not listen.

## The steps that remain, and who does them

1. **The loop**: the packaging step (the quarantine attribute, the signature check, the
   screenshots in the required sizes), the metadata and the privacy policy of this directory,
   the **export recipe** with its placeholders, the display name of the app and the rehearsal
   that proves every property of the built artefact.
2. **The operator**: the Apple Developer account (the trader status), the *Apple
   Distribution* certificate and the *Mac App Distribution* profile, the team id in the
   archive, the publication of the privacy policy and the support URL, the answers of the
   app privacy details and the age rating, the **instance for the reviewer**, and finally the
   **upload** itself.
3. **Not by anybody without the operator's decision**: the submission and the publication.
