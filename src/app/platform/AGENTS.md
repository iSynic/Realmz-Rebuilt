# Application platform contract

## Purpose

Own process lifecycle, presentation-only preferences, and debug-build host facilities.

## Ownership

- `ApplicationLifecycleHost` coordinates process Quit, End Adventure, Save and Quit, and deferred close interactions.
- `ApplicationLifecycle` is the pure option and decision policy for those host transitions.
- `ApplicationSettingsController` binds and persists presentation settings.
- `DebugToolsHost` exposes typed debug commands only in debug builds.
- `RuntimeTestingHost`, `RuntimeTestingEndpoint`, `RuntimeTestingConnection`, `RuntimeTestingProtocol`, and `RuntimeTestingObserver` own the opt-in developer testing boundary. Explicit debug launch plus `REALMZ_TESTING_HOME` publishes a private per-process authenticated descriptor on an ephemeral IPv4 loopback port. The strict versioned JSON vocabulary, request-result ledger, revision guard, and live read-only gate precede command dispatch. Bounded recent diagnostics identify omitted history; checkpoint export uses `GameSession.snapshot` and `SaveEnvelope` without bypassing unavailable continuation states. The MCP/CLI service lives in `tools/runtime_testing`; Providence preview remains a separate unchanged protocol.
- `DevelopmentPreviewRequest` owns the strict developer-only request vocabulary shared with Providence. `DevelopmentPreviewSession` validates the temporary package through the ordinary application-plus-scenario boundary, creates the deterministic in-memory party, and enters an Action Point, Simple, Complex, or owner-bound Thief Encounter, standalone Extra Action Point program, map location, exact scenario-owned scrolling `TEXT`, or exact Classic Battle, Treasure, or Shop target. Complex, Thief, Battle, Treasure, and Shop readiness requires the ordinary typed interaction surface; a Thief target enters through the exact owning Complex Encounter's authored action. Extra Action Point program preview accepts only exact `xap:<id>` ownership and explicitly omits Timed, hook, item, random-rectangle, and other caller context. Direct Shop preview is unrestricted because caller-owned acceptance ranges are not part of `Data SD`. `DevelopmentPreviewResultWriter` owns the strict result envelope. Export-excluded tools provide the headless and interactive hosts; public release startup never selects them.

## Local Contracts

- Process Quit and End Adventure are distinct operations.
- Settings may affect presentation, input cadence, renderer choice, sound, and accessibility; they never alter deterministic game truth.
- Debug commands enter through the typed public debug boundary and never appear in release UI or saves.
- Automated mutations are fixture-only. Ordinary semantic commands retain application modal/input/playback gates; direct invocation uses the debug boundary and cannot certify ordinary trigger eligibility or caller context. Credentials, personal checkpoints, and captures stay local, never in public artifacts or routine tool results.
- Cancelled or failed lifecycle operations leave both process and session active.

## Work Guidance

- Keep operating-system notifications at this boundary and game lifecycle decisions in public session operations.
- Keep setting defaults and persistence synchronized with `src/storage/settings`.

## Verification

- Run `tests/presentation/test_classic_ui_system.gd` and the settings repository suite for affected work.
- Run native smoke verification for process-lifecycle changes.

## Child DOX Index
