# OIP open release tasks

This checklist is the progress file for the `oip-open-release-tasks` OpenCode loop. This is a build loop: implement and verify the open OTA work. Do not spend turns searching for general issues, auditing unrelated code, or repeating findings. The loop reads this file on every run and stops when every item is completed or is marked `BLOCKED` with the exact missing operator input and supporting evidence.

## Goal

Close the software work that is still open for the first public OIP macOS release, starting with the broken end-to-end GitHub OTA offer and installation. Before each work item, read `AGENTS.md`, `docs/OIP_RELEASE_PROGRESS.md`, `docs/OIP_RELEASE_LEDGER.md`, and `docs/evidence/oip-github-ota/ota-receipt.json`.

## Tasks

- [x] Reproduced the updater failure: installed version `0.3.0` build `3` completed a fresh check but did not offer signed release `v0.3.1` build `4`; evidence is in `docs/evidence/oip-github-ota/ota-receipt.json`.
- [ ] Implement the root-cause fix in the native updater now. Add a focused regression test for the failing offer path and validation failures; keep diagnostics useful and local. Do not produce an issue list instead of code.
- [ ] Review and correct the installer helper relaunch behavior. It must safely replace the app, verify the replacement, roll back on failure, and relaunch without reporting success prematurely.
- [ ] Exercise the real update path from the installed `0.3.0+3` app to the latest signed release. Verify the installed bundle version/build, strict code signature, running process path, and clean rollback state. Record measurements in the OTA receipt and release progress.
- [ ] Reconcile `docs/OIP_RELEASE_LEDGER.md`: finish software-ready tasks; identify exact operator or external dependency blockers with the needed evidence. Do not turn a blocked operator gate into repeated code work.

## Acceptance

- The installed app discovers a newer GitHub release and gives the operator a clear update action or an equivalent explicit, user-facing update flow.
- The app rejects invalid manifests, signatures, archive digests, bundle identities, versions, and unsafe download URLs; automated tests cover these paths.
- A real signed update reaches the installed app, starts successfully from `/Applications`, and leaves no rollback backup behind. A forced post-swap launch failure proves rollback restores the prior bundle.
- The OTA receipt, release progress, and ledger match observed results. Do not claim an end-to-end OTA pass without the real installed-version measurement.
- Every remaining release item is either proven complete with evidence or marked blocked with the specific operator action/dependency and why the loop cannot perform it.

## Work rules

- Follow `AGENTS.md`: use an isolated branch/worktree, verify changes there, and integrate with `git merge --ff-only`. Preserve the canonical UI contract and update authoritative progress/evidence.
- Build priority: each loop turn must either implement code, add/repair a focused test, run a test/build required by that change, or complete a measured OTA install step. No general issue-hunting turns. If a focused test fails, fix the code in the same workstream; do not pivot to an audit.
- Make one bounded, evidence-backed improvement per turn. Do not repeat clean analyzer/test runs as progress.
- Respect the repository rules on the personal installation database, schema-7 activation, foreign worktrees/processes, and private SSH. Do not connect to bodi-pi, bodi-pc, the OpenWrt router, or Hue bridge unless the repository instructions and supplied credentials authorize that specific acceptance.
- Do not push commits, publish a new GitHub release, deploy, submit to an App Store, or claim Store readiness from this loop. Prepare and verify the candidate locally, update the receipt, and report the exact approval needed before any publication. The already-published `v0.3.1` is available for the installed-client OTA check.
- If a step needs operator access or unavailable credentials, record the exact missing input and mark that item `BLOCKED`. Do not retry the same blocker or invent cosmetic work.
- Stop only when every checklist item is complete or precisely blocked. Report measured results and remaining operator actions.
