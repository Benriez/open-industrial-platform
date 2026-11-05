# Independent Review B — IPC & Authorization

Reviewer: `/root/review_security_007`. Explicit OIP-007 Phase K delegation, read-only. No edits or processes changed. Initial usage interruption occurred after concrete findings; review later resumed and completed.

## Findings and closure

- B-01 LOW: protection attributes only checked before opening file. Descriptor type/UID/mode/linkcount/size/inode are rechecked.
- B-02 MEDIUM: blocking socket probe, then insufficient stale proof. Saturated Unix backlog can return ConnectionRefused on macOS. Fixed by bounded probe plus protected persisted dev/ino/ctime/ns identity, exclusive lock and re-stat before unlink. Unrecorded/foreign live socket preserved in actual saturated-backlog test.
- B-03 MEDIUM: blocking stdout could retain bridge after session close. Fixed shared safe Tokio Unix pipe Sender over duplicated OwnedFd, three-second write bound, no global stdout-lock worker. Real open-stdin/unread-stdout test self-exits, other MCP client/Flutter/ingestion continue.
- B-04 authority-model correction: explicit read-only daemon rest_policy is validated/injected instead of implicit REST grants.

The initial tiny-snapshot test did not saturate stdout: bulk.* is intentionally excluded from Snapshot. The corrected test uses actual100-node tool results. Its final unread pipe contains65536bytes and the bridge reports stdout-stall timeout. Earlier harness failures are not evidence that those tiny snapshots physically blocked a pipe.

## Final reviewer conclusion

"Unabhängiges Review B — IPC & Autorisierung: abgeschlossen. Keine offenen Blocker im geprüften lokalen Entwicklungs-Vertrauensmodell."

Reviewer independently inspected kernel peer UID use, protected directory/config/credentials, bounded prelude/deadline, session/request limits, frozen server policy, scopes/resource denials, mutation lockout, SDK framing and redaction. Reviewer read nine IPC tests PASS and final12-phase E2E PASS; did not claim independent execution of the entire regression suite.

Reviewed source hashes:
- ipc.rs f89119d53c9d0476b039927fb9e5559e43e3e9c1539d28fb8d9345e0fe9c7654
- transport.rs 63be60cc10b101ed7db705c8f7a786646c214f0c3d53e3f2fffc6dd26db65b53
- main.rs 47ebc98331c9c4d3acdf26f64fbdd1f698bc73ae153f02351e859b24d484b9d1

Limits: same OS owner remains trusted and can access its credentials; SourceScope is not tenant isolation; configured REST authority is separate. Other real OS-user execution, Linux and non-pipe launchers not claimed. Operator stderr sink can still block logging; durable bounded audit remains future work. No production clearance.
