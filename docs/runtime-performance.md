# Runtime performance evidence

Measured through 2026-09-01 with Godot 4.7.1 on Windows and an NVIDIA GeForce RTX 3080 at the canonical 1280x720 and native 3440x1440 profiles. Machine timings are evidence for this pass, not portable guarantees.

## Scope and boundaries

This pass covers launch-video scheduling, last-campaign preparation, Character Files insertion, dependency-driven exploration projection, retained overworld presentation, and deterministic combat pursuit. It does not change opcode behavior, package trust, overworld movement speed, splash timing, scenario data, or GUI design.

## Rendering method

Native releases default to Godot's Mobile RenderingDevice path. On the measured Windows system this resolves to Vulkan; the same project retains `--rendering-method gl_compatibility --rendering-driver opengl3` as an explicit fallback for older or problematic hardware. The renderer choice does not enter presentation settings, saves, packages, or simulation state because Godot establishes it before project scripts run.

The equal-workload AOGM `land:0` probe used 400 percent cadence, 400 ordinary rules-enabled moves, eighty warmup frames, the same package and retained scene, disabled VSync, and forced unswapped GPU completion. Mobile/Vulkan improved frame and post-draw tails at both measured sizes without changing transaction/projection time or producing skipped intervals:

| Viewport / method | Frame p95 / p99 / max | Post-draw p95 | Skipped / catch-up |
|---|---:|---:|---:|
| 1280x720 Compatibility/OpenGL | 4.656 / 5.826 / 7.117 ms | 2.534 ms | 0 / 0 |
| 1280x720 Mobile/Vulkan | 3.943 / 5.072 / 6.136 ms | 1.695 ms | 0 / 0 |
| 3440x1440 Compatibility/OpenGL | 4.911 / 6.130 / 7.051 ms | 2.808 ms | 0 / 0 |
| 3440x1440 Mobile/Vulkan | 4.198 / 5.174 / 7.008 ms | 1.849 ms | 0 / 0 |

This supports Mobile as the default but does not reclassify CPU-side simulation or projection work as a renderer responsibility. `runtime_performance_probe.gd` records the resolved rendering method and driver in every subsequent report so results from different backends cannot be silently aggregated.

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

Ordinary movement now scales with changed state. `GameView` carries a nonserialized `ViewChangeSet` and independent roster, status, inventory, and magic revisions. Hourly SP recovery always advances status and magic revisions, but spell records are copied only when structural legality changes or an affordability threshold is crossed. Equipment facts remain cached by inventory revision. Previous detached snapshots retain their original scalar and component records.

The map read model is an 8x8 copy-on-write `MapWindowView`. Adjacent movement shares unchanged chunks and creates only entering-strip, destination, overlay, discovery, and LOS-edge cells. A bounded coordinate/revision cache reuses an already-detached LOS window. Resize, map/topology change, restore, Wizard's Eye expansion, and unknown events request a complete rebuild; topology, collision, visited, and visibility truth remain in simulation.

Normal rendering no longer redraws every terrain cell through `Control._draw()`. One clipped SubViewport retains base, six ordered feature, marker, and fog `TileMapLayer` surfaces, pooled CICN `Sprite2D` overlays, and a `Camera2D`. The presenter applies only `MapPresentationDelta` coordinates on ordinary travel. Debug facts, cursors/selections, and the minimap remain custom Control drawing.

The original rules-enabled baseline was 135.804 ms combined p95 when an hourly recovery forced a complete `GameView`. The final isolated probe uses six depleted level-10 casters with four spells each and at least 4,096 explored cells. Its latest run reports 0.500 ms transaction p95, 0.697 ms projection p95, and 1.175 ms combined p95; hourly transaction and projection p95 are 0.616 and 0.885 ms. No-clip is not part of either acceptance probe.

The rendered probe uses normal `PlayerIntent.move`, real AOGM map media, five-minute Classic timeclicks, repeated hourly recovery, and separate ordinary/hourly samples. A benchmark-only snapshot moves authored timed encounters beyond the measurement window so a modal timeline cannot replace a travel sample. Eighty warm frames allocate retained layers and driver resources before measurement. Vsync is disabled; native GPU completion uses an unswapped forced draw so the 120 Hz engine-work measurement is not capped by the physical monitor.

Current 1280x720 results (five seconds per run):

| AOGM map / cadence | Combined p95 | Frame p95 / p99 / max | Hourly combined / frame p95 | Schedule |
|---|---:|---:|---:|---|
| `land:0` ordinary, 100% | 2.017 ms | 6.924 / 7.135 / 7.147 ms | 2.113 / 6.910 ms | 0 skipped, 0 catch-up |
| `land:0` ordinary, 400% | 1.600 ms | 4.939 / 6.295 / 6.979 ms | 1.777 / 5.690 ms | 0 skipped, 0 catch-up |
| `land:2` darkness, 100% | 1.929 ms | 6.941 / 6.965 / 7.029 ms | 2.230 / 6.935 ms | 0 skipped, 0 catch-up |
| `land:2` darkness, 400% | 1.606 ms | 4.860 / 7.443 / 9.555 ms | 2.054 / 6.018 ms | 0 skipped, 0 catch-up |
| `land:4` LOS, 100% | 2.033 ms | 6.930 / 6.951 / 6.964 ms | 2.276 / 6.940 ms | 0 skipped, 0 catch-up |
| `land:4` LOS, 400% | 1.703 ms | 4.863 / 6.832 / 7.898 ms | 1.835 / 5.005 ms | 0 skipped, 0 catch-up |

Native 3440x1440 runs on the same machine also passed at both cadences for ordinary, darkness, and LOS travel. The final-build 400% runs completed 400 measured moves in approximately five seconds with zero skipped or catch-up intervals; combined p95 remained 1.703 ms or lower, frame p95 remained 5.957 ms or lower, frame p99 remained 7.796 ms or lower, and no frame exceeded 11.252 ms. Hour-boundary combined and frame p95 remained at or below 1.936 and 7.670 ms. The latest native LOS 100% run reported 2.742 ms combined p95, 7.703 ms frame p95, 9.921 ms p99, and 10.208 ms maximum. These results meet the 3.0/8.3/12.5/16.7 ms acceptance thresholds without reducing the visible tile count, native cell size, interface density, or simulation frequency.

## Combat navigation

Party Auto and monster advance now request a weighted route to every legal hostile contact position before committing a movement step. Each edge uses the same complete-footprint maximum terrain charge as actual movement; a rules-legal size-zero friendly swap is represented by its actual five-point edge. Four derived 1x1, 1x2, 2x1, and 2x2 profiles retain static passability and destination movement base until battlefield terrain changes; typed distance, first-step, closed, goal, heuristic, queue, and heap storage is reused with generation counters. Other dynamic combatants block the immediate move but remain forecast occupancy later in the route. If no route exists, monsters retain Castle's deterministic bounded random shifting.

The tool-only `battlefield_navigation_benchmark.gd` compared ten repeated decisions for every combination of six fixtures and four footprint shapes. It subclasses `AStarGrid2D` only inside the probe so both planners use the same footprint passability and exact edge cost; the engine comparator runs one query per legal contact goal because it has no native multi-goal contract. Across 240 decisions, the custom planner took 5.071 seconds and `AStarGrid2D` took 3.770 seconds. All twenty reachable fixture/footprint combinations agreed on the first step, and all four unreachable cases agreed that no route existed. Routine open, choke, and congestion means were 1.34-2.43 ms for the custom planner versus 1.07-3.53 ms for the engine comparator. U-shaped detours remained the largest reachable custom cost at 31.29-35.08 ms; unreachable full-field exhaustion measured 79.11-80.14 ms versus 46.15-64.80 ms. The native engine search is therefore still faster in the worst cases, but it remains comparison infrastructure: the custom planner preserves stable tie-breaking, exact multi-cell rules, multi-goal pursuit, query-time occupancy semantics, and the Node-free deterministic core boundary.

## Verification boundary

Focused startup, package/prewarm, vault, session, presentation, architecture, and aggregate checks own deterministic correctness. The native rendered probe owns the frame measurements above. Godot MCP Pro was not available in the active tool surface for this run, so these results do not claim the separately required MCP-controlled playable walkthrough; that limitation remains explicit rather than treating headless or debug travel as ordinary-play certification.
