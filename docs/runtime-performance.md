# Runtime performance evidence

Baseline measurements run through 2026-09-05; shared-resource revalidation below is dated 2026-09-10. Both use Godot 4.7.1 on Windows and an NVIDIA GeForce RTX 3080 at the canonical 1280x720 and native 3440x1440 profiles. Machine timings are evidence for these passes, not portable guarantees.

## Scope and boundaries

This pass covers launch-video scheduling, last-campaign preparation, Character Files insertion, dependency-driven exploration projection, retained overworld presentation, and deterministic combat pursuit. It does not change opcode behavior, package trust, overworld movement speed, splash timing, scenario data, or GUI design.

## Rendering method

Native releases default to Godot's Mobile RenderingDevice path. On the measured Windows system this resolves to Vulkan; the same project retains `--rendering-method gl_compatibility --rendering-driver opengl3` as an explicit fallback for older or problematic hardware. The renderer choice does not enter presentation settings, saves, packages, or simulation state because Godot establishes it before project scripts run.

The original equal-workload AOGM `land:0` renderer comparison used 400 percent cadence, 400 ordinary rules-enabled moves, eighty warmup frames, the same package and retained scene, disabled VSync, and forced unswapped GPU completion. Mobile/Vulkan improved frame and post-draw tails at both measured sizes without changing transaction/projection time or producing skipped intervals. That comparison used the former alternating two-cell route, so it remains valid only as a renderer-backend comparison and is not current traversal certification:

| Viewport / method | Frame p95 / p99 / max | Post-draw p95 | Skipped / catch-up |
|---|---:|---:|---:|
| 1280x720 Compatibility/OpenGL | 4.656 / 5.826 / 7.117 ms | 2.534 ms | 0 / 0 |
| 1280x720 Mobile/Vulkan | 3.943 / 5.072 / 6.136 ms | 1.695 ms | 0 / 0 |
| 3440x1440 Compatibility/OpenGL | 4.911 / 6.130 / 7.051 ms | 2.808 ms | 0 / 0 |
| 3440x1440 Mobile/Vulkan | 4.198 / 5.174 / 7.008 ms | 1.849 ms | 0 / 0 |

This supports Mobile as the default but does not reclassify CPU-side simulation or projection work as a renderer responsibility. `runtime_performance_probe.gd` records the resolved rendering method and driver in every subsequent report so results from different backends cannot be silently aggregated.

The user-provided diagnostic baseline was approximately 9.1 seconds to application readiness, 0.45 seconds for warm Tutorial preparation, 4.1 seconds cold and 1.95 seconds warm for the 52.8 MiB Wrath package, and 3.2 ms p95 for ordinary movement transaction plus projection. Those figures predate this checkout's final instrumentation and are retained as the comparison baseline rather than rewritten as current measurements.

## Completed architecture certification

The completed architecture tree was compared with the archived pre-migration production tree on the same Windows host. The baseline tree was run through the final probe contract without changing its production source. Each value below is the median of three warmed samples; lower is better.

| Probe | Pre-migration | Completed tree | Result |
|---|---:|---:|---|
| Application ready | 9,847.479 ms | 9,203.296 ms | 6.54% faster |
| First frame | 54.317 ms | 40.822 ms | 24.85% faster |
| Movement transaction plus projection p95 | 2.094 ms | 1.811 ms | 13.52% faster |
| Movement transaction p95 | 1.091 ms | 0.683 ms | 37.40% faster |
| Movement projection p95 | 1.278 ms | 1.139 ms | 10.88% faster |
| 3D dungeon unique-step p95 | 8.365 ms | 5.602 ms | 33.03% faster |
| Battle setup | 112.968 ms | 84.114 ms | 25.54% faster |
| Combat view | 2.026 ms | 1.242 ms | 38.70% faster |
| Auto activation | 36.361 ms | 27.268 ms | 25.01% faster |
| Warm monster phase | 9.938 ms | 8.165 ms | 17.84% faster |
| Native 3440x1440 frame p95 | 6.198 ms | 5.852 ms | 5.58% faster |
| Native transaction plus projection p95 | 2.457 ms | 2.345 ms | 4.56% faster |

The completed 1280x720 rendered samples additionally measured 5.319 ms median frame p95 and 1.936 ms median transaction-plus-projection p95. All six rendered samples retained the full 240-move route, approximately 79.4 admitted steps per second, zero skipped intervals, zero catch-up bursts, and the existing visible-cell and simulation cadence. The 52.81 MiB Wrath package measured 8,182 ms against the prior 8,075 ms reference; the 107 ms increase is 1.33 percent and therefore does not cross both package rejection thresholds.

The exact local Windows candidate exports a 109,071,360-byte executable and 153,000,388-byte PCK. The same-workspace pre-migration export produced the identical executable size and a 152,531,636-byte PCK, so the PCK grew 0.31 percent and the combined artifact grew 0.18 percent. Three clean two-second headless smoke launches measured a 217,632,768-byte median peak working set against 221,937,664 bytes for the same three-run pre-migration export, a 1.94 percent reduction. The comparison created no second checkout, and its temporary baseline artifact was removed after measurement.

## Launch and menu video

The front door prepares one OGV decoder behind the opaque splash, starts it before reveal, retains it while covered, and reveals active playback. MP3 materialization remains demand-driven. Remaining construction stays on the existing threaded scene-loading boundary.

The 2026-09-03 front-door scene conversion used a controlled three-run comparison against its immediate parent commit because the earlier 38.354 ms first-frame sample was no longer reproducible on the same host. The parent measured 163.854–192.630 ms to first frame, 7,038.000–7,420.576 ms of background loading, and 7,230.192–7,608.897 ms to application readiness. The authored-scene branch measured 160.620–177.842 ms, 6,857.613–7,781.371 ms, and 7,018.000–7,958.842 ms respectively. That overlapping range shows no material startup regression; it is not evidence of a general speedup. Every run kept the menu absent and the launch card present on the first frame, prepared and played exactly one decoder, retained it for five menu seconds, enabled the scenario action, and completed the queued transition.

The five-scene character-creation conversion initially exposed four new step scenes as eager `PackedScene` dependencies and exceeded the startup budget, so those major workspaces were changed to editor-visible scene paths cached on first use; their variable row/component scenes remain exported `PackedScene` dependencies of the owning step. An interleaved three-run comparison against the immediate parent then measured parent medians of 160.338 ms to first frame, 7,349.759 ms of background loading, and 7,555.425 ms to application readiness. The accepted lazy-scene branch measured 155.377 ms, 6,980.143 ms, and 7,135.644 ms respectively. The ranges remained host-variable, so this is evidence of no material regression rather than a claimed speedup. Every run retained the launch-card, single-decoder, enabled-action, and queued-transition invariants.

The subsequent Character Files browser and setup-inspection scene conversion retained the same boundary. Its interleaved three-run parent medians were 153.165 ms to first frame, 6,559.447 ms of background loading, and 6,712.389 ms to application readiness; the authored-scene branch measured 144.533 ms, 6,436.285 ms, and 6,580.609 ms. This likewise establishes no material regression without claiming a general improvement.

## Scenario preparation

Presentation settings schema 12 optionally retains the stable identity of the last successfully started campaign. Once the menu video and application shell are stable, the package host prepares that resolved campaign on its existing cancellable worker and retains at most one validated candidate. Selecting the same campaign claims it synchronously; selecting another supersedes the background operation with foreground priority. Integrity, manifest, receipt, schema, and immutable-install validation are unchanged. Initial media hydration is limited to the active map and currently visible character assets.

The claim/supersede/cancel/retry contract is automated and bounded, but direct validation throughput has not improved on this machine: two current full reads of the installed 52.81 MiB Wrath package took 8,013 ms and 8,075 ms. The player-visible gain is the responsive background preparation and immediate retained-candidate claim for the last campaign, not a claimed reduction in cold validation cost. A different, unprepared campaign remains cancellable but can still take several seconds.

## Character insertion

Validated vault revisions are cached by character identity and revision hash when listed. Add and drop import a detached clone from that cache, invalidated by vault publication, archive, restore, or refresh. Six stable party-slot Controls are retained and only the changed slot is rebound. Portrait drag cursors are prepared per portrait revision before drag/drop.

The rendered Tutorial runs measured cached vault-import p95 at 0.208 ms (400 percent run) and 0.240 ms (100 percent run), with one validated revision retained. Automated coverage separately proves detached imports, invalidation, six stable slots, shared Add/drop intent, and cached drag art.

## Overworld traversal

Ordinary movement now scales with changed state. `GameView` carries a nonserialized `ViewChangeSet` and independent roster, status, inventory, and magic revisions. Hourly SP recovery always advances status and magic revisions, but spell records are copied only when structural legality changes or an affordability threshold is crossed. Equipment facts remain cached by inventory revision. Previous detached snapshots retain their original scalar and component records.

The map read model is an 8x8 copy-on-write `MapWindowView`. Adjacent movement shares unchanged chunks and creates only entering-strip, destination, overlay, discovery, and LOS-edge cells. A typed empty chunk is allocated before a patch crosses into a previously absent 8x8 region; the prior untyped empty-array expression failed at those boundaries and could leave the camera advanced against a stale retained edge. A nonserialized per-map cell cache derives reusable static detached facts once per map/topology/effective-region/landlook revision, so entering-strip cost no longer scales with repeated feature and edge reconstruction at native width. A bounded coordinate/revision cache reuses an already-detached LOS window. Resize, map/topology change, restore, Wizard's Eye expansion, and unknown events request a complete rebuild; topology, collision, visited, and visibility truth remain in simulation.

The ordinary adjacent-movement builder keeps visibility, bounds, cache selection, movement options, and final `MapView` construction in one bounded hot path without allocating an intermediate projection wrapper. Cold complete-window construction and copy-on-write patching remain named helpers. This preserves the human-readable ownership boundary while avoiding a per-step abstraction cost at native resolution.

Normal rendering no longer redraws every terrain cell through `Control._draw()`. One clipped SubViewport retains base, six ordered feature, marker, and fog `TileMapLayer` surfaces, pooled CICN `Sprite2D` overlays, and a `Camera2D`. The host projects one guard cell beyond each clipped visible edge, and the presenter applies only `MapPresentationDelta` coordinates on ordinary travel. Debug facts, cursors/selections, and the minimap remain custom Control drawing.

The original rules-enabled baseline was 135.804 ms combined p95 when an hourly recovery forced a complete `GameView`. The final isolated probe uses six depleted level-10 casters with four spells each and at least 4,096 explored cells. Its latest run reports 0.500 ms transaction p95, 0.697 ms projection p95, and 1.175 ms combined p95; hourly transaction and projection p95 are 0.616 and 0.885 ms. No-clip is not part of either acceptance probe.

The 2026-09-05 detached-projector ownership pass used three immediate-parent and three changed AOGM samples. Median transaction-plus-projection p95 changed from 1.294 ms to 1.282 ms, overall projection p95 from 0.808 ms to 0.834 ms, ordinary projection p95 from 0.470 ms to 0.519 ms, and hourly projection p95 from 1.066 ms to 0.945 ms. The 0.049 ms ordinary-path increase is below the 0.20 ms absolute rejection floor; all six runs admitted all sixty steps through the incremental path and produced identical event-sequence counts.

The character-rule and detached-copy readability pass used three warmed before and three warmed after AOGM samples. Median transaction p95 changed from 0.474 ms to 0.455 ms, projection from 0.789 ms to 0.787 ms, combined transaction-plus-projection from 1.239 ms to 1.231 ms, ordinary projection from 0.459 ms to 0.471 ms, and hourly projection from 0.817 ms to 0.835 ms. Every run admitted all sixty steps through the incremental path; the small projection changes are below the 0.20 ms absolute rejection floor and do not establish a general speedup or regression.

The combat-magic target-family readability pass used three immediate-parent and three changed AOGM Battle 46 samples. Median Auto activation changed from 24.604 ms to 24.610 ms, battle setup from 75.413 ms to 75.477 ms, spell-option construction from 2.133 ms to 2.145 ms, combat-view construction from 1.220 ms to 1.232 ms, complete monster phase from 6.404 ms to 6.435 ms, warm monster phase from 6.204 ms to 6.166 ms, and checkpoint serialization from 0.270 ms to 0.276 ms. All deltas are below the 0.20 ms absolute rejection floor; every sample retained the same setup, Auto, and monster-phase event sequences, 2,718 total RNG draws, 32 monster-phase draws, and 84 spell options.

The combat-lifecycle readability pass used three immediate-parent and three changed AOGM Battle 46 samples. Median Auto activation changed from 24.404 ms to 24.881 ms, battle setup from 75.325 ms to 75.601 ms, spell-option construction from 2.142 ms to 2.137 ms, combat-view construction from 1.236 ms to 1.215 ms, complete monster phase from 6.357 ms to 6.295 ms, warm monster phase from 6.273 ms to 6.187 ms, and checkpoint serialization from 0.273 ms to 0.267 ms. Auto and setup increased by 1.95 and 0.37 percent respectively, so neither exceeds the combined percentage and absolute rejection thresholds; the other directly measured paths were flat or faster. Every sample retained the same setup, Auto, and monster-phase event sequences, 2,718 total RNG draws, 32 monster-phase draws, and 84 spell options.

The physical-combat readability pass reused those three changed samples as its exact immediate-parent baseline and added three samples of the final command and attack phase split. Median Auto activation changed from 24.881 ms to 24.462 ms, battle setup from 75.601 ms to 76.323 ms, spell-option construction from 2.137 ms to 2.123 ms, combat-view construction from 1.215 ms to 1.186 ms, complete monster phase from 6.295 ms to 6.449 ms, warm monster phase from 6.187 ms to 6.216 ms, and checkpoint serialization from 0.267 ms to 0.265 ms. Setup and the complete monster phase increased by 0.96 and 2.45 percent respectively, so neither exceeds the combined percentage and absolute rejection thresholds; the remaining paths were flat or faster. Every sample retained the same setup, Auto, and monster-phase event sequences, 2,718 total RNG draws, 32 monster-phase draws, and 84 spell options.

The exploration-continuation and map-window readability pass used three immediate-parent and three changed AOGM movement samples. Median transaction p95 changed from 0.459 ms to 0.457 ms, projection from 0.785 ms to 0.837 ms, transaction-plus-projection from 1.231 ms to 1.292 ms, ordinary projection from 0.446 ms to 0.469 ms, and hourly transaction from 0.479 ms to 0.571 ms. Every delta remains below the 0.20 ms absolute rejection floor; all samples retained sixty incremental projections, the same final coordinate, event sequences, and fatigue payload.

The rendered probe uses normal `ExplorationIntents.move`, real AOGM map media, five-minute Classic timeclicks, repeated hourly recovery, and separate ordinary/hourly samples. It now derives a long cardinal route between farthest reachable cells, reports its bounds and unique-cell count, and crosses retained 8x8 chunk boundaries; the former two-cell loop is explicitly insufficient. A benchmark-only snapshot moves authored timed encounters beyond the measurement window and zeroes random-region chance so a modal timeline cannot replace a travel sample. Eighty warm frames allocate retained layers and driver resources before measurement. Vsync is disabled; native GPU completion uses an unswapped forced draw so the 120 Hz engine-work measurement is not capped by the physical monitor.

The prior six-map matrix used the now-rejected two-cell route and is superseded for traversal acceptance. The current 2026-09-01 regression used AOGM `land:0`, a 155-cell route spanning `(1,5)` through `(26,79)`, 240 measured moves in three seconds at 400 percent cadence, normal rules, and one guard cell per visible edge:

| Viewport | Combined p95 | Frame p95 / p99 / max | Hourly combined / frame p95 | Schedule |
|---|---:|---:|---:|---|
| 1280x720 | 1.851 ms | 6.948 / 7.190 / 12.515 ms | 2.111 / 6.947 ms | 0 skipped, 0 catch-up |
| 3440x1440 | 2.270 ms | 6.186 / 10.603 / 11.498 ms | 2.575 / 7.486 ms | 0 skipped, 0 catch-up |

Both long-route runs crossed multiple retained chunks without a script error, completed at approximately 79.4 steps per second, and met the 3.0/8.3/12.5/16.7 ms thresholds without reducing visible tile count, native cell size, interface density, or simulation frequency. Darkness and LOS long-route recertification remains separate from this non-LOS chunk-boundary regression rather than inheriting the superseded two-cell evidence.

## Combat navigation

Party Auto and monster advance now request a weighted route to every legal hostile contact position before committing a movement step. Each edge uses the same complete-footprint maximum terrain charge as actual movement; a rules-legal size-zero friendly swap is represented by its actual five-point edge. Four derived 1x1, 1x2, 2x1, and 2x2 profiles retain static passability and destination movement base until battlefield terrain changes; typed distance, first-step, closed, goal, heuristic, queue, and heap storage is reused with generation counters. Other dynamic combatants block the immediate move but remain forecast occupancy later in the route. If no route exists, monsters retain Castle's deterministic bounded random shifting.

The tool-only `battlefield_navigation_benchmark.gd` compared ten repeated decisions for every combination of six fixtures and four footprint shapes. It subclasses `AStarGrid2D` only inside the probe so both planners use the same footprint passability and exact edge cost; the engine comparator runs one query per legal contact goal because it has no native multi-goal contract. Across 240 decisions, the custom planner took 5.071 seconds and `AStarGrid2D` took 3.770 seconds. All twenty reachable fixture/footprint combinations agreed on the first step, and all four unreachable cases agreed that no route existed. Routine open, choke, and congestion means were 1.34-2.43 ms for the custom planner versus 1.07-3.53 ms for the engine comparator. U-shaped detours remained the largest reachable custom cost at 31.29-35.08 ms; unreachable full-field exhaustion measured 79.11-80.14 ms versus 46.15-64.80 ms. The native engine search is therefore still faster in the worst cases, but it remains comparison infrastructure: the custom planner preserves stable tie-breaking, exact multi-cell rules, multi-goal pursuit, query-time occupancy semantics, and the Node-free deterministic core boundary.

The route-readability extraction used three warmed immediate-parent and three changed ten-iteration samples of the same 24 fixture/footprint matrix. Custom-planner totals were 4.067, 4.036, and 4.068 seconds before the change and 4.005, 4.020, and 4.041 seconds after it, moving the median from 4.067 to 4.020 seconds. Every changed sample retained all 24 expected reachable first-step or unreachable outcome agreements. The extraction therefore introduces no measured route regression.

The final presentation-function split used three committed-parent and three changed synthetic dungeon-transition samples. Median unique-step p95 changed from 4.326 to 4.590 ms, turn p95 from 0.018 to 0.016 ms, and backtrack p95 from 0.034 to 0.043 ms. Unique-step increased by 6.10 percent but only 0.264 ms, below the combined rendered-presentation rejection threshold of both five percent and 0.50 ms; the other absolute deltas were negligible. Every sample retained 32 geometry builds and 78 cache hits and remained well inside the 8.3 ms unique-step and 1 ms turn/backtracking budgets.

## Verification boundary

Focused startup, package/prewarm, vault, session, presentation, architecture, and aggregate checks own deterministic correctness. The native rendered probe owns the frame measurements above. Godot MCP Pro was not available in the active tool surface for this run, so these results do not claim the separately required MCP-controlled playable walkthrough; that limitation remains explicit rather than treating headless or debug travel as ordinary-play certification.

## Shared-resource library revalidation

The 2026-09-10 working-tree check pairs War package `19234678a99a5c1cb05c83da702aebe2372b41877cf1e1637f31d29d16b39d9e` with application library `82b8718f183bb07135ca0438d833c534754e16361314759b83e5192ccb55cbad`. The rendered probe now retains the same application media source used for package validation and rejects missing or undecodable map atlases before measurement. Earlier runs that omitted that source do not establish this replacement's rendering performance.

Two ten-second Mobile/Vulkan runs use the same 202-step War overworld route, 102 distinct cells, eighty warmup frames and 400-percent cadence. At 1280x720, transaction-plus-projection p95 is 2.515 ms and frame p95/p99/max is 5.798/7.370/16.142 ms; the gate passes. At native 3440x1440, those values are 2.785 ms and 5.925/7.922/17.302 ms; one frame exceeds the 16.7 ms maximum, so that run fails. Both resolve and decode the scenario's land atlas, traverse all 102 cells, report zero skipped/catch-up intervals, and record one gameplay-boundary segment restart. This is absolute-budget evidence, not an equal-workload before/after regression comparison.

Repeated native diagnosis attributes the first-hour-after-restore spike to releasing a stale roster-held view, not map drawing. The shell now honors the detached complete-refresh flag even when restored domain revisions resemble ordinary movement. With temporary instrumentation removed, the same route at 3440x1440 measures frame p95/p99/max of 5.451/7.059/12.320 ms, but combined CPU p95 of 3.007 ms and hourly CPU p95 of 3.089 ms still fail the 3 ms gate. The renewed 1280x720 run passes with combined CPU p95 2.661 ms and frame p95/p99/max 5.276/7.133/16.496 ms. Both traverse all 102 route cells with one boundary restart and no missed/catch-up intervals. The affected shell, System and Builder suites pass 993 assertions. This closes the diagnosed restore-refresh defect, not native performance acceptance or an equal-workload regression comparison; timed runs complete different sample counts.

The probe now accepts an optional sixth user argument for an exact movement-frame count, bounded by the existing duration ceiling, and records canonical start/end save hashes after timing. Two native baseline and two tentative unchanged-cell-reuse runs each complete exactly 600 moves, 411 ordinary and 189 hourly samples, the same direction counts, all 102 route cells and identical start/end saves. Baseline combined CPU p95 is 3.758/3.172 ms; tentative reuse is 3.179/3.361 ms. Every run fails the CPU gate, and the change has no consistent benefit, so the cell-reuse edit is removed. A separate running Godot game was observed consuming CPU and left untouched; the measurements do not isolate its contribution. Invalid counts and duration-limited incomplete counts reject explicitly. These checks improve comparison reproducibility without relaxing any budget.

The attempted dungeon-zero run rejects before measurement: that map has no passable cells. Other War dungeons have passable cells but none meeting this probe's feature-free route policy. No dungeon performance claim follows from this attempt. Separate canonical fixtures now observe a War dungeon, its actual Torch control and the authored chapel Battle 335, plus Bywater's actual Area Search and exact stock secret marker. The battle journey reaches rendered combat but exceeds diagnostic trace capacity; it does not establish complete combat replay. The marker replay fixes a source-proven land-secret LOS error, changes exactly the 222 nonwhite source-marker pixels and no other map pixels, and retains a byte-identical resulting save. These bounded visual/control checks are not performance samples. Native CPU-budget acceptance, dungeon performance and broader ordinary gameplay remain open.
