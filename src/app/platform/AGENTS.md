# Application platform contract

## Purpose

Own process lifecycle, presentation-only preferences, and debug-build host facilities.

## Ownership

- `ApplicationLifecycleHost` coordinates process Quit, End Adventure, Save and Quit, and deferred close interactions.
- `ApplicationLifecycle` is the pure option and decision policy for those host transitions.
- `ApplicationSettingsController` binds and persists presentation settings.
- Display settings reconfigure the retained compositor and spatial zoom in place. The runtime testing bridge reports window-space control rectangles and captures the displayed outer viewport when that compositor is present; fixture UI clicks still enter the application viewport through its own control identity.
- `DebugToolsHost` exposes one presentation-only F12 Diagnostics overlay from the front door through active play. It edge-latches raw and polled physical F12 input so exported builds cannot miss or double-toggle the surface, and admits typed mutation commands, event history, and the console only in debug builds. Its dialog may be temporarily reparented to the front-door overlay but returns to the application before handoff.
- `RuntimeTestingHost`, `RuntimeTestingEndpoint`, `RuntimeTestingConnection`, `RuntimeTestingProtocol`, `RuntimeTestingObserver`, and `RuntimeTestingReadiness` own the opt-in developer testing boundary. Explicit debug launch plus `REALMZ_TESTING_HOME` publishes a private per-process authenticated descriptor on an ephemeral IPv4 loopback port. The strict versioned JSON vocabulary, request-result ledger, revision guard, and live read-only gate precede command dispatch. Bounded recent diagnostics identify omitted history; readiness distinguishes committed, presented, presentation-drawn, deferred, playback-frame, and transport revisions; checkpoint export uses `GameSession.snapshot` and `SaveEnvelope` without bypassing unavailable continuation states. The MCP/CLI service lives in `tools/runtime_testing`; Providence preview remains a separate unchanged protocol.
- `RuntimeTestingFixtureRequest` validates a scratch-contained launch before composition; `RuntimeTestingFixtureSession` validates application/scenario packages and prepares the exact pinned six starter records through validated snapshot restore, or restores an unchanged checkpoint. Named preparation recomputes derived inventory load, explicitly commits setup, and positions the party without claiming ordinary Character Files import eligibility or the campaign-start hook. `RuntimeTestingCommands` uses public host movement, intent, and response paths; direct AP/XAP/encounter/Battle/Treasure/Shop targets retain existing debug ownership restrictions. `RuntimeTestingUi` catalogs bounded visible controls and sends real viewport mouse or device-zero controller input, never control signals or property writes. Its observations include the stable visible focus identity, and controller input remains testable while playback or a host dialog owns the actual application boundary. Captures require a post-draw frame of the current monotonic bridge revision and write only fixture-owned paths.
- `DevelopmentPreviewRequest` owns the strict developer-only request vocabulary shared with Providence. `DevelopmentPreviewSession` validates the temporary package through the ordinary application-plus-scenario boundary, creates the deterministic in-memory party, and enters an Action Point, Simple, Complex, or owner-bound Thief Encounter, standalone Extra Action Point program, map location, exact scenario-owned scrolling `TEXT`, or exact Classic Battle, Treasure, or Shop target. Complex, Thief, Battle, Treasure, and Shop readiness requires the ordinary typed interaction surface; a Thief target enters through the exact owning Complex Encounter's authored action. Extra Action Point program preview accepts only exact `xap:<id>` ownership and explicitly omits Timed, hook, item, random-rectangle, and other caller context. Direct Shop preview is unrestricted because caller-owned acceptance ranges are not part of `Data SD`. `DevelopmentPreviewResultWriter` owns the strict result envelope. Export-excluded tools provide the headless and interactive hosts; public release startup never selects them.

## Local Contracts

- Process Quit and End Adventure are distinct operations.
- Settings may affect presentation, input cadence, renderer choice, sound, and accessibility; they never alter deterministic game truth.
- Debug commands enter through the typed public debug boundary and never appear in release UI or saves.
- Retail diagnostics can persist only the default-off AP/random-rectangle presentation preference; the host does not construct or connect retail mutation, logging, or console routes.
- The retail dialog call must receive a typed empty `Array[Dictionary]` for map records; an untyped conditional empty-array branch cannot cross its typed method boundary.
- Automated mutations are fixture-only. Ordinary semantic commands retain application modal/input/playback gates; direct invocation uses the debug boundary and cannot certify ordinary trigger eligibility or caller context. Credentials, personal checkpoints, and captures stay local, never in public artifacts or routine tool results.
- Bridge revisions never rewind on checkpoint restore. Recent diagnostics remain bounded; complete diagnostic requests expose the existing trace-capacity limit explicitly rather than silently certifying incomplete traces. Fixture close waits for queued replies to drain before process termination.
- Fixture controller button releases and exact axis-neutral events bypass only a stale revision mismatch so a held input can always be stopped while scheduled gameplay advances; presses, directions, ordinary UI actions, and every live-session mutation retain the revision and read-only gates.
- Complete observations may include detached snapshot-derived RNG and gameplay state only while the public snapshot boundary permits it; unavailable continuations remain explicit null values. Party observations preserve current/max spell points, derived load, conditions, and inventory for fixture comparison. Render readiness may expose presentation-only combat media diagnostics: requested facing resource, resolved owner/hash, and whether the established base fallback was used.
- The testing wire adapter restores JSON integer types before strict interaction-body decoding, with a bounded nesting depth. It does not relax the gameplay interaction codecs.
- Testing replies, checkpoint hashes, retry fingerprints, and byte-limit accounting use the same sorted full-precision JSON encoding. Checkpoint transport must not round gameplay values; package canonical hashing remains separate and unchanged.
- Named Classic starter preparation uses Castle `setupnewgame`'s quest-zero sentinel `-1` before the baseline checkpoint. This is explicit fixture context, not an ordinary campaign-start claim; checkpoint clones never rewrite it.
- Cancelled or failed lifecycle operations leave both process and session active.

## Work Guidance

- Keep operating-system notifications at this boundary and game lifecycle decisions in public session operations.
- Keep setting defaults and persistence synchronized with `src/storage/settings`.

## Verification

- Run `tests/presentation/test_classic_ui_system.gd` and the settings repository suite for affected work.
- Run native smoke verification for process-lifecycle changes.

## Child DOX Index
