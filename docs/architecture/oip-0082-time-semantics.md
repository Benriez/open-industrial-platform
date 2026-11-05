# OIP-008.2 — Time Semantics

| Field | Meaning | Query ordering |
|---|---|---|
| Observation.timestamps.source | Device/source clock, may be invalid, delayed or virtual | Preserved, never relabeled receive time |
| Observation.timestamps.server | Optional OPC-UA server clock | Preserved, never substituted for source time |
| Observation.timestamps.received | Actual adapter receive clock when present | Historical observation range/keyset |
| DiagnosticEvent.at_ms | Original stored event timestamp; observation events use source time, control events collector/runtime event time | Event history range/keyset |
| CollectionGap.documented_start/end_ms | Original recorded markers | Gap start-marker range/keyset |
| SourceHealthTransition.at_ms | Runtime clock when dimensions were actually observed for publication | Health history range/keyset |

No global synchronized causal timeline is asserted. A late receive is not live at SourceTimestamp. Source/server/runtime clock agreement is unknown. Explicit calendar ranges accept the established OPC date domain1601..9999; invalid supplied ranges fail. Unfiltered events/detail still retain any originally preserved out-of-domain/sentinel i64 timestamp for forensic inspection. No replacement zero timestamp, interpolation, gap filling, synthesized averages/minmax/sample counts or invented values.

Historical observation envelopes and embedded observation events are marked Stale when served; original values, quality, timestamps, status/error and simulation provenance remain. This is a read projection and does not modify stored rows. Missing receive timestamps are excluded from receive-time history and identified as unavailable; clients may examine observation events by source time instead. There is no assumed timestamp fallback.

Health.previous=null means the process has no prior recorded dimension state, including after restart. Run recovery does not make old samples Fresh: existing runtime restore keeps observation Stale, source freshness Unknown, runtime last_received=null until actual new reception. A failed real probe may change reachability. Prior health records remain historical evidence and do not override runtime freshness. History coverage gaps around process crashes or persistence failures are explicitly possible.
