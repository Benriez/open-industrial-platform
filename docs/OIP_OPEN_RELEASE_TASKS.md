# OIP live stability acceptance loop

This is a focused build-and-verify loop for the live OIP app. Do not search for unrelated issues, write issue lists, repeat completed audits, or switch to a different model. Read `AGENTS.md`, `docs/OIP_RELEASE_PROGRESS.md`, and this file before every run. Preserve the current `model-router` agent and its selected `bodi-benny/ornith-122b` model.

## Goal

Make the installed OIP app's API connection stable enough to use the OPC-UA browser, then verify real telemetry from `bodi-pi` and `bodi-pc`. Continue with concrete implementation or measured acceptance work until the items below are proven complete. Do not treat a published build, a single HTTP 200, or a simulated/demo result as acceptance.

## Tasks

- [x] Reproduce the live API stall and isolate it to the macOS app-owned SSH tunnel. Evidence: repeated `18858` timeouts/resets/no-listener while Pi Core remained healthy; independent `18859` tunnel returned 12/12 HTTP 200; installed OIP LaunchAgent plist was stale on port `18854`.
- [x] Fix tunnel ownership/configuration in the macOS app. The app now generates its OIP tunnel and watchdog LaunchAgents from its configured ports and keeps the tunnel under `launchd`. Source revision: `dfd58ff`.
- [x] Publish OTA `v0.3.10` build `13` locally, without GitHub Actions. Signed archive SHA-256: `cf07581a34316019dc7c0b2aa245ac137d9783806fbf0e47948090611894cd33`.
- [ ] Install `0.3.10+13` through the app's OTA flow and restart the installed app. Never force-quit or self-install over a running app without explicit operator authorization. Current evidence: `/Applications` still runs `0.3.9+12`; the restart/install confirmation is pending in the operator conversation.
- [ ] After installation, verify the generated LaunchAgent forwards `127.0.0.1:18858` to `bodi-pi:18808`, confirm the watchdog is loaded, and probe the API repeatedly over at least ten minutes. Record status, response codes, latency, process restarts, and logs in `docs/OIP_RELEASE_PROGRESS.md`.
- [ ] In the installed app, choose one authorized OPC-UA source and verify browsing, selected-node reads, and live telemetry for both `bodi-pi` and `bodi-pc`. Record actual values and observation timestamps; no fixture or simulated data counts.
- [ ] If a measured check fails, fix that specific client/Core defect, build and publish through the local OTA publisher (never GitHub Actions), install only through the approved app update flow, and repeat the failed acceptance checks.

## Run rules

- Work only on the next unchecked task. Make a concrete source change or capture new runtime evidence on each run; do not repeat issue hunting.
- Keep `model-router` with the session's selected `bodi-benny/ornith-122b` model. Do not pass an alternate provider/model to loop commands or fall back to an OpenCode model.
- Do not start GitHub Actions. Use `tools/oip_ota_release.sh` for any needed OTA publication.
- Respect `AGENTS.md`: isolate source edits in a worktree and merge with `git merge --ff-only`; update the authoritative progress file. Do not alter the personal installation database or schema.
- Do not use simulation data. Do not force-quit the app, install over the running app, or claim an update is installed without explicit operator authorization and a measured installed version.
- If a task depends on the pending restart approval, record that exact dependency once and wait for operator input; do not retry the same blocked action or invent another task.

## Completion

Complete the loop only after the installed app is `0.3.10+13` or later, the repeated API check passes, the OPC-UA browser works on an authorized source, and real telemetry from both hosts is observed with fresh timestamps. Update `docs/OIP_RELEASE_PROGRESS.md` with the measurements. Report any remaining blocker plainly.
