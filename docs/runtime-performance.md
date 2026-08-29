# Runtime performance evidence

Measured 2026-08-29 with Godot 4.7.1 Compatibility/OpenGL on Windows, an NVIDIA GeForce RTX 3080, and the canonical 1280x720 application profile. Machine timings are evidence for this pass, not portable guarantees.

## Scope and boundaries

This pass covers launch-video scheduling, last-campaign preparation, Character Files insertion, and ordinary overworld presentation. It does not change opcode behavior, package trust, movement speed, splash timing, scenario data, or GUI design.

The user-provided diagnostic baseline was approximately 9.1 seconds to application readiness, 0.45 seconds for warm Tutorial preparation, 4.1 seconds cold and 1.95 seconds warm for the 52.8 MiB Wrath package, and 3.2 ms p95 for ordinary movement transaction plus projection. Those figures predate this checkout's final instrumentation and are retained as the comparison baseline rather than rewritten as current measurements.

## Launch and menu video

The front door prepares one OGV decoder behind the opaque splash, starts it before reveal, retains it while covered, and reveals active playback. MP3 materialization remains demand-driven. Remaining construction stays on the existing threaded scene-loading boundary.

The current startup probe reports 38.354 ms to the first splash frame, 6,834 ms of background application loading, and 7,006.726 ms to application readiness. The menu was absent and the supplied splash present on the first frame. At menu reveal the intro was already playing, had been prepared exactly once, and exactly one prepared decoder existed. Playback and that single-decoder count remained unchanged for five additional menu seconds before a scenario transition succeeded.

## Scenario preparation

Presentation settings schema 12 optionally retains the stable identity of the last successfully started campaign. Once the menu video and application shell are stable, the package host prepares that resolved campaign on its existing cancellable worker and retains at most one validated candidate. Selecting the same campaign claims it synchronously; selecting another supersedes the background operation with foreground priority. Integrity, manifest, receipt, schema, and immutable-install validation are unchanged. Initial media hydration is limited to the active map and currently visible character assets.

The claim/supersede/cancel/retry contract is automated and bounded, but direct validation throughput has not improved on this machine: two current full reads of the installed 52.81 MiB Wrath package took 8,013 ms and 8,075 ms. The player-visible gain is the responsive background preparation and immediate retained-candidate claim for the last campaign, not a claimed reduction in cold validation cost. A different, unprepared campaign remains cancellable but can still take several seconds.

## Character insertion

Validated vault revisions are cached by character identity and revision hash when listed. Add and drop import a detached clone from that cache, invalidated by vault publication, archive, restore, or refresh. Six stable party-slot Controls are retained and only the changed slot is rebound. Portrait drag cursors are prepared per portrait revision before drag/drop.

The rendered Tutorial runs measured cached vault-import p95 at 0.208 ms (400 percent run) and 0.240 ms (100 percent run), with one validated revision retained. Automated coverage separately proves detached imports, invalidation, six stable slots, shared Add/drop intent, and cached drag art.

## Overworld traversal

Ordinary same-map movement emits a nonserialized presentation delta containing the viewport shift and only newly visited/seen coordinates. Unknown events, restores, map transitions, interactions, and LOS changes still force complete projection. The shell's ordinary path updates only coordinates, clock, fatigue, light, and map presentation. The map presenter retains decoded atlas/overlay textures and visible-cell state across adjacent steps.

The deterministic session-only probe seeds 4,096 visited coordinates and reports 0.496 ms transaction p95, 2.175 ms projection p95, and 2.610 ms combined p95 across 60 ordinary steps. That probe does not claim draw performance.

The rendered acceptance probe uses Tutorial `land:0`, not a tileless fixture: 90x90 and 8,100 authored cells, resolved `landlook-10` atlas (640x320, 32x32 tiles, 527,686 bytes), and 14 overlay asset identities. Its deterministic 8,366-tile route spans the complete `[0,0]-[89,89]` map and covers 8,012 unique coordinates through horizontal, vertical, and diagonal sweeps. Adjacent debug no-clip avoids AP/collision pauses while using the same incremental map and shell presentation path; ordinary transaction behavior remains covered by the session probe.

| Run | Distance / unique cells | Actual cadence | p95 / p99 / max movement frame | 60 Hz gate | 120 Hz tier |
|---|---:|---:|---:|---|---|
| Tutorial 400% for 30.025 s | 2,399 / 2,266 | 79.901 steps/s | 10.636 / 14.615 / 17.982 ms | Pass: 0 over 20 ms, 0 over 33.3 ms | Miss: p95 and p99 exceed 8.3/12.5 ms |
| Tutorial 100% for 30.025 s | 600 / 508 | 19.983 steps/s | 11.281 / 14.919 / 17.171 ms | Pass: 0 over 20 ms, 0 over 33.3 ms | Miss: p95 and p99 exceed 8.3/12.5 ms |

The 400 percent run had zero queued catch-up bursts and one skipped schedule window; the missed window was discarded rather than replayed. The 100 percent run had neither a skipped interval nor a catch-up burst. Both satisfy the hard 60 Hz release target. The optional 120 Hz target remains open.

## Verification boundary

Focused startup, package/prewarm, vault, session, presentation, architecture, and aggregate checks own deterministic correctness. The native rendered probe owns the frame measurements above. Godot MCP Pro was not available in the active tool surface for this run, so these results do not claim the separately required MCP-controlled playable walkthrough; that limitation remains explicit rather than treating headless or debug travel as ordinary-play certification.
