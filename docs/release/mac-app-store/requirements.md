# The Mac App Store readiness of the OIP client (the checklist of the official requirements)

The requirements were read on **2026-11-11** from the official sources of Apple. Every
row names its source. A row that is not **MET** is not a claim: it is either a piece of
work that the loop delivers or an **operator action** (the identity of the developer, the
certificate, the account). Nothing here is the permission to submit or to publish.

## The current official requirements

| # | Requirement | Source (read 2026-11-11) | State of OIP | What closes it |
|---|---|---|---|---|
| R1 | The apps uploaded to App Store Connect must be built with **Xcode 26** or later (since 2026-04-28) | <https://developer.apple.com/news/upcoming-requirements/> (`SDK minimum requirements`) | **MET** — the machine of the release builds with Xcode 26.6 | — |
| R2 | The app must declare the **approved reasons for the required-reason APIs** it uses (since 2024-05-01) | <https://developer.apple.com/news/upcoming-requirements/> (`Approved reasons for APIs`), <https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk> | **OPEN** — the bundle carries no `PrivacyInfo.xcprivacy` | the privacy manifest of the app (`PrivacyInfo.xcprivacy`) + the packaging check |
| R3 | The macOS apps uploaded to App Store Connect must **not** carry the extended attribute `com.apple.quarantine` on any file (since 2025-02-18) | <https://developer.apple.com/news/upcoming-requirements/> (`Quarantine attribute in macOS apps`) | **OPEN** — the release bundle carries no quarantine attribute today; the *upload* must not create one | the packaging step strips it and the check asserts it |
| R4 | The **hardened runtime** must be enabled for the app and the command line targets | <https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution> (`Prepare your software for notarization`) — the same protection the App Store submission checks; the direct distribution of G9/N17 needs it in any case | **OPEN** — `ENABLE_HARDENED_RUNTIME` is not set in the Xcode project | the Release and Profile configurations of the Xcode project |
| R5 | The Mac App Store requires the **app sandbox** | the App Store submission (the equivalent security checks of the store) | **MET** — `com.apple.security.app-sandbox` is in `Runner/Release.entitlements` | — |
| R6 | The entitlements of the notarisation must be **XML and ASCII**, the code signing must cover **every executable**, with a **secure timestamp**, and **no** `com.apple.security.get-task-allow` | <https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution> | **OPEN** — the packaging check must read the signature of every executable of the bundle | the packaging + verification script |
| R7 | The **privacy policy URL** and a **support URL** are required on the product page | <https://developer.apple.com/app-store/app-privacy-details/> (`Privacy links`), <https://developer.apple.com/distribute/app-review/> | **OPEN** — the texts exist in this directory; the **public URLs** are the operator's | the operator publishes the two URLs |
| R8 | The **app privacy details** must state every data type that the app collects | <https://developer.apple.com/app-store/app-privacy-details/> | **OPEN** — the answers are prepared (`metadata.md`): the client collects **nothing** off the device | the answers of the operator in App Store Connect |
| R9 | The **icon** of the app (1024×1024) and the **screenshots** of the app in the required sizes | <https://developer.apple.com/app-store/submitting/> | **PARTIAL** — the icon exists in the asset catalogue; the screenshots in the required sizes are **not** yet produced | the screenshot step of the packaging script |
| R10 | The **signing** of the upload uses the *Mac App Distribution* profile and the *Apple Distribution* certificate of the developer | <https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution> (the certificate types: for the store the *Apple Distribution*, for the direct distribution the *Developer ID*) | **OPERATOR** — the identity, the certificate and the profile belong to the operator | the operator's archive |
| R11 | The **notarisation** uses `notarytool` (not `altool`, since 2023-11-01) and the ticket is stapled | <https://developer.apple.com/news/upcoming-requirements/> (`Apple notary service update`) | **N/A for the store** — the App Store submission already includes the equivalent checks; `notarytool` is the path of the **direct** distribution (G9/N17) | the runbook of the direct distribution |
| R12 | The **age rating** uses the updated questions (since 2026-01-31) | <https://developer.apple.com/news/upcoming-requirements/> (`Age Rating Updates`) | **OPEN** — the answers are prepared (no objectionable content, no user content) | the answers of the operator |
| R13 | The **trader status** is required for the EU | <https://developer.apple.com/news/upcoming-requirements/> (`DSA trader status`) | **OPERATOR** — it belongs to the developer account | the operator's account |

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

1. **The loop**: the hardened runtime, the privacy manifest, the packaging step
   (the quarantine attribute, the signature check, the screenshots in the required sizes),
   the metadata and the privacy policy of this directory, and the rehearsal that proves
   every property of the built artefact.
2. **The operator**: the Apple Developer account (the trader status), the *Apple
   Distribution* certificate and the *Mac App Distribution* profile, the team id in the
   archive, the publication of the privacy policy and the support URL, the answers of the
   app privacy details and the age rating, and finally the **upload** itself.
3. **Not by anybody without the operator's decision**: the submission and the publication.
