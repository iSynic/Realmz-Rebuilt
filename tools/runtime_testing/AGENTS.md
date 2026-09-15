# Runtime testing transport

## Purpose

Own the local Realmz runtime-testing observation and fixture transport package: strict protocol schemas, loopback service, session discovery, MCP v2 stdio tools, CLI, and focused protocol tests.

## Ownership

- Own `realmz-testing/1` request/reply framing, the engine-facing client, and descriptor discovery under `REALMZ_TESTING_HOME`.
- Own credential handling, loopback-only connections, replay protection, and access/revision gates at this transport boundary.
- Own isolated fixture process launching, bounded journey orchestration, private evidence, and normalized comparison. Engine adapters retain gameplay behavior and validation.

## Local Contracts

- All requests and replies are newline-delimited JSON and limited to 16 MiB including the newline.
- Request IDs are non-empty and limited to 128 characters; a changed body under an existing ID returns `request_id_conflict`.
- Connections target `127.0.0.1` only; descriptor paths remain below the explicit discovery root.
- Discovery reads at most 256 regular, non-symlink descriptor files and rejects descriptor files over 64 KiB.
- Tokens stay in local descriptor files and authenticated internal requests; they are excluded from sanitized discovery, MCP results, and transport logs.
- Mutating commands require `expectedRevision`; observe-access sessions reject them service-side. Isolated fixture button releases and exact axis-neutral events may cross an intervening revision so held gameplay can always be stopped; all initiating input retains optimistic concurrency. A caller may retry an ambiguous mutation only with the same explicit `requestId`.
- MCP input and wire replies are strict Zod schemas. Advertise only implemented capabilities.
- Fixture launches use explicitly configured engine/project paths, unique scratch roots, distinct Godot/stdout logs, the canonical 1280x720 Mobile rendered target, and a visible fixture title. Native fixture children set `GODOT_MCP_HEADLESS_CHILD=1` to isolate them from editor-driven MCP autoload services. Clone requires a valid exported checkpoint and matching validated package; never inject into or restart a live process.
- Named fixture preparation may position provenance-pinned starter characters before recording the baseline. Checkpoint clones preserve captured state and RNG exactly. Journeys cannot restore or reseed between steps.
- Fixture config is strict and records package/source hashes plus the exact Git `HEAD` and honest dirty-source fingerprint for Rebuilt. Rebuilt accepts only `engine: rebuilt` and the named `classic-starters` recipe; Castle accepts only the bounded `native-griloch-starters` recipe and writes its exact nine-field `castle-fixture` config to `config.json`. Fixture readiness is observed by `fixtureId`.
- Castle launchers require `REALMZ_CASTLE_PATH`, `REALMZ_CASTLE_ROOT`, and the pinned Rebuilt starter source. They validate the Castle base ancestor, copy the six exact Character Files into fixture `userdata/Character Files`, compare every installed Grilochs Revenge scenario file byte-for-byte with the Castle checkout, and pass `REALMZ_CASTLE_TEST_CONFIG` plus `REALMZ_TESTING_HOME` to a detached process. Castle advertises only its implemented native movement, Shop/Done UI, AP, observation, capture, checkpoint, and close capabilities; its checkpoint is a non-restorable native observation and is never treated as a Rebuilt SaveEnvelope.
- Classic starter coordinates are bounded to the inclusive 0..32767 map range. Exported checkpoints use exclusive unique paths under fixture or live checkpoint roots, and their engine canonical hash remains distinct from the retained file hash.
- `capture` is a read command. `restore`, `act`, `respond`, `ui`, `invoke`, and `close` remain generic engine commands with explicit revision/request identity; fixture lifecycle helpers expose only the bounded create/clone/checkpoint/restore/close/capture operations.
- Fixture `ui` accepts observed pointer controls plus bounded button and axis events for device zero. Controller events enter the real normalized application input owner, remain available while playback or a host dialog owns input, and report the resulting focus identity. Live sessions continue to reject every `ui` mutation service-side.
- Journeys are strict, persistent asynchronous jobs under `REALMZ_TESTING_HOME/jobs`; CLI and MCP share `spec.json`, `status.json`, `cancel`, and retained `evidence.json` artifacts. Workers are detached/unref'd and never execute arbitrary scripts. Each step polls semantic readiness, submits the immediately observed revision, preserves the exact accepted input and request identity, records bounded complete diagnostics, and stops on pending-interaction, stale, unsupported, cancellation, timeout, action-limit, trace-capacity, or evidence-capacity failures. Journeys require an isolated fixture baseline checkpoint and never restore or reseed between steps.
- Journey comparison normalizes named semantic gameplay fields only, ignores documented request/timing/build/path and capture-binary fields, and reports `initialEquivalenceVerified: false` when the saved baselines cannot establish equivalent party, location, time, inventory/wealth, scenario, and RNG state.
- `comparison.ts` owns complete Rebuilt baseline comparison and the provenance-pinned `griloch-ap52/1` native profile. Missing state, unknown profiles, failed steps, or saturated traces cannot report equality. Native executable hashes identify installed binaries independently from source commits.

## Work Guidance

- Keep this package standalone and Node/TypeScript based. Do not add engine changes or global/client configuration.
- Keep fake loopback engine behavior confined to `test/support`; the production CLI/MCP path connects to the real engine endpoint.
- Use the official MCP TypeScript SDK v2 package/imports pinned in `package.json`.
- Keep tests against fake loopback peers focused on protocol behavior; do not claim engine gameplay behavior from transport mocks.

## Verification

- `npm run build`
- `npm test`

## Child DOX Index

No child DOX documents.
