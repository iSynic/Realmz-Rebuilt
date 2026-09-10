# Runtime testing bridge

The developer-only bridge connects isolated game fixtures, observations, actual UI input, and recorded journeys to one local MCP/CLI service in `tools/runtime_testing`. It is disabled by default and cannot be enabled in a release build. Providence's preview request remains unchanged. Godot MCP Pro remains the editor/general-inspection route.

## Access and identity

An explicitly launched debug/source runtime accepts `--realmz-testing-observe` after Godot's `--` argument separator. `REALMZ_TESTING_HOME` must name an absolute local tooling directory outside player storage. `REALMZ_TESTING_BUILD` labels the inspected build; an absent label is reported as `unversioned-source`, never inferred to be a verified commit.

This does not attach to, inject into, or restart an existing runtime. Observe-mode instances use ordinary application behavior but the bridge cannot submit inputs, restore, close, or otherwise mutate the live adventure. Checkpoint export returns the public save-v4 envelope, or `snapshot_unavailable` when no safe snapshot exists. It does not fabricate an intermediate state.

Each process creates a random session identity and 256-bit authentication secret, binds an ephemeral port on `127.0.0.1`, and publishes `sessions/<sessionId>.json` beneath the tooling directory. Keep that directory private to the local user. Descriptors are credentials; do not commit or share them. Discovery validates process identity through an authenticated request rather than trusting stale files. Ordinary results omit the token. Graceful shutdown removes only the process's own descriptor.

## Engine protocol

The transport is one UTF-8 JSON request and one JSON reply per TCP connection, each terminated by a newline and bounded to 16 MiB including the newline. No binary object decoding, arbitrary script, property mutation, or network-selected filesystem path is supported. Incremental nonblocking I/O runs on the engine's main thread; complete validated commands execute at application frame boundaries.

Requests contain exactly `protocol`, `sessionId`, `token`, `requestId`, `expectedRevision`, `command`, and `params`. The protocol is `realmz-testing/1`. `expectedRevision` is null or a nonnegative safe integral revision; mutations require it. Read commands are `describe`, `observe`, `checkpoint`, and fixture-only `capture`. Observation accepts an empty object for recent diagnostics or `{ "diagnostics": "complete" }` for the bounded complete trace. Other reads accept empty parameters. Descriptors advertise actual supported capabilities; a known but unimplemented command returns an explicit error.

Replies contain exactly `protocol`, `sessionId`, `requestId`, `revision`, `ok`, `result`, and `error`. An error has `code` and `message`; a successful reply has a null error. Authorization and session identity are checked before dispatch. Reusing a request identity with identical input returns its recorded reply even after a revision change. Reusing it with different input fails. Stale requests cannot mutate. After uncertain delivery, retry only the identical request identity and payload.

The bounded retry ledger retains up to 10,000 replies within a 256 MiB reservation budget. At capacity it rejects further commands instead of forgetting a previously executed mutation. Recent observations explicitly label bounded diagnostic history; they are not a complete journey recording.

## Fixture preparation and commands

See [the tooling README](../tools/runtime_testing/README.md) for dependencies, environment variables, and local registration. The service exposes `realmz_sessions`, `realmz_observe`, `realmz_fixture`, `realmz_act`, `realmz_respond`, `realmz_ui`, `realmz_invoke`, `realmz_journey`, `realmz_capture`, and `realmz_compare`.

Rebuilt fixtures run the export-excluded `tools/runtime_testing_host.tscn` at 1280x720 with the Mobile renderer. Before application construction, the strict launch request establishes unique scratch saves, settings, Character Files, installations, and logs. Every window is labelled `TEST FIXTURE`. A malformed request fails closed; it never falls back to ordinary application startup.

The named `classic-starters` fixture loads the pinned application library and validates the supplied scenario archive. It restores detached copies of the exact six Realmz 7.1.2 starter records, recomputes derived inventory load, marks preparation complete, and positions the party through the existing debug boundary. This bounded setup does not certify ordinary Character Files eligibility or the campaign-start hook. A checkpoint clone instead restores the validated snapshot unchanged, including its RNG state. Record the package, application library, starter revisions, source commit, dirty-source fingerprint, and checkpoint hash with the baseline.

| Command | Supported Rebuilt input |
| --- | --- |
| `act` | Named adjacent movement, dungeon turn, area search, search toggle, torch, contextual encounter, camp, rest, heal, and service actions; ordinary application gates apply. |
| `respond` | Exact current `requestId`, interaction `kind`, and validated typed response `body`. |
| `ui` | Mouse press/release delivered to one currently visible, enabled, unoccluded catalogued control. No signals or properties are written. |
| `invoke` | Exact AP, standalone XAP program, Simple/Complex encounter, owner-bound Thief encounter, or unrestricted Shop through existing debug commands. |
| `restore` | Validated save envelope; replacement occurs only after validation succeeds. |
| `close` | Fixture-only process close after queued protocol replies drain. |

The bridge revision is monotonic within a process, independently of restored gameplay revisions. Complete observations include snapshot-derived state only when the public snapshot boundary permits it; unavailable debug/continuation snapshots remain null. Screenshots require a rendered frame of the current bridge revision. Ordinary failures retain the submitted typed intent or interaction and its exact error.

## Recorded journeys

Journeys are persistent jobs shared by CLI and MCP, with status and cancellation available after the initiating client exits. Each step declares a command, parameters, expected interaction kind, optional expected location, and optional screenshot. Defaults are 200 actions and 120 seconds; larger runs need explicit limits. Readiness polling observes semantic and rendered boundaries without skipping simulation or presentation work. `$pending` resolves only an interaction response's request identity.

Jobs retain the baseline checkpoint, accepted request identities and inputs, before/after observations and revisions, state differences, RNG and VM trace deltas, failures, and capture references outside Git. They stop on unexpected interaction, errors, stale state, unsupported capability, cancellation, or capacity limits. The inclusive evidence bound is 256 MiB. Conservative space reservations stop before another action when its evidence cannot fit; failed evidence is never automatically deleted. Existing engine trace capacity is reported explicitly rather than silently treating truncated history as complete.

## Castle mirror

Castle instrumentation belongs in a separate worktree based on `491816ad60037394f92c428e99c004494d3c28b3`, behind the default-off `REALMZ_RUNTIME_TESTING` CMake option. The minimal native fixture uses Castle's own loaders, the same six pinned Character Files, and the byte-verified installed Griloch scenario. It does not import Rebuilt saves. Its user-data override takes effect before filesystem initialization, and its native checkpoint is observation-only, not restorable.

Native movement and the visible Shop/Done controls run through Castle's normal input paths. Direct invocation is restricted to Griloch AP `Data DD:0:52`. A test-only raw RNG matches Rebuilt's generator while preserving Castle's `Rand` scaling; it is aligned once after fixture preparation and never reseeded during a journey. Engine-specific unsupported targets remain errors. Comparison must establish initial party, inventory, wealth, time, location, relevant scenario state, and RNG equivalence before inspecting later differences; missing normalization never establishes parity.

## Evidence boundaries

Ordinary gameplay must route through application commands and respect modal and playback gates. Actual UI execution must deliver input to visible controls through normal routing. Direct AP/XAP/encounter invocation uses the separate debug boundary and cannot certify movement, trigger eligibility, caller context, or one-shot semantics. Automated commands belong only to isolated fixture instances; a live checkpoint may be cloned without taking control of its source.

The initial acceptance target is Grilochs Revenge, land 0 at 8,20. Direct AP results alone cannot close that ordinary-entry report. Castle comparison must establish equivalent native fixture inputs and report unsupported capabilities or unexplained differences explicitly. Source-control-flow, integration, rendered UI, ordinary-play, and Castle-runtime evidence remain separate claims.
