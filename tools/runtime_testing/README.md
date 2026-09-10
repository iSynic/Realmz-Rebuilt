# Realmz runtime testing transport

This package is the local observation/fixture transport foundation for the Realmz runtime. It provides:

- a loopback-only TCP newline-delimited JSON service with a 16 MiB request/reply limit (including the newline);
- strict Zod validation for the `realmz-testing/1` request, reply, and discovery-descriptor envelopes;
- authenticated session discovery under `REALMZ_TESTING_HOME\sessions`, with stale descriptors ignored after a live `describe` probe;
- request-ID replay protection, explicit revision checks for mutations, and service-side observe-mode mutation rejection;
- a standalone `realmz-testing` CLI and an MCP v2 stdio server exposing `realmz_sessions`, `realmz_observe`, and isolated fixture create/clone/checkpoint/restore/close/capture operations.

The package launches only explicit isolated Rebuilt or Castle fixtures; it does not inject into or restart live adventures. The CLI and MCP server connect to the engine's loopback endpoint after launch; tests use fake loopback peers under `test/support` only for transport and protocol behavior.

## Local development

```powershell
$env:REALMZ_TESTING_HOME = 'C:\path\to\local\runtime-testing-home'
npm install
npm run build
npm test
npm run mcp
```

The environment variable is intentionally required for discovery. Descriptor files contain the private session token and should stay in the local discovery root. MCP and CLI results never include that token. No global or client configuration is written by this package.

## Isolated Rebuilt fixtures

Fixture creation additionally requires `REALMZ_GODOT_PATH` and `REALMZ_REBUILT_ROOT`. The only named preparation recipe currently accepted is `classic-starters`, with a bounded seed and explicit map location. Clone requires an exported checkpoint and a caller-supplied `.realmz2` package. The launcher uses the native rendered canonical target (never headless):

```text
godot --path <REALMZ_REBUILT_ROOT> --resolution 1280x720 --rendering-method mobile --log-file <fixtureRoot>/engine.log res://tools/runtime_testing_host.tscn -- <fixtureRoot>/fixture.json
```

Standard output and error are retained separately in `<fixtureRoot>/stdout.log`. Native fixture children receive `GODOT_MCP_HEADLESS_CHILD=1` so unrelated editor-driven Godot MCP autoload services do not poll or delete shared user files. Exported checkpoints are retained at unique `checkpoints/<uuid>.r2save` paths; the engine's canonical `sha256` remains distinct from the saved file hash.

Each fixture receives a unique 32-hex ID under `<REALMZ_TESTING_HOME>/fixtures`, private config/checkpoint/log files, package/source hashes, and a build identity containing the exact Git `HEAD` plus either `clean` or a dirty-source fingerprint. Readiness is semantic (`observe.result.readiness.fixtureReady`); startup timeout or cancellation leaves artifacts in place and does not kill an unknown wrapper process. Fixture descriptors are discovered by `fixtureId`, never by parent PID.

## Isolated Castle fixtures

Castle creation requires `REALMZ_CASTLE_PATH`, `REALMZ_CASTLE_ROOT`, and `REALMZ_REBUILT_ROOT`. The only accepted recipe is `native-griloch-starters` using public source `classic-starters`, seed `1..2147483646`, and Grilochs Revenge `land:0` at `(7,20)` (or `(8,20)` for the direct baseline). The launcher passes no executable arguments and supplies only the private config and testing-home environment variables:

```text
Realmz.exe   (cwd <fixtureRoot>, REALMZ_CASTLE_TEST_CONFIG=<fixtureRoot>/config.json, REALMZ_TESTING_HOME=<home>)
```

`config.json` has exactly nine top-level fields: `protocol`, `kind`, `fixtureId`, `scratchRoot`, `discoveryRoot`, `build`, `seed`, `location`, and `identity`. Its identity pins the Castle base commit `491816ad60037394f92c428e99c004494d3c28b3`, instrumentation `HEAD` plus dirty-source fingerprint, all six Character File hashes, and every byte-matched installed Grilochs Revenge scenario file. The six pinned starter files are copied to `<fixtureRoot>/userdata/Character Files` before launch. Castle readiness requires `fixtureReady`, `semanticReady`, and `visualReady`; its checkpoint result is a `native-observation` snapshot with `restorable: false`, so Castle fixtures cannot be cloned or restored as Rebuilt SaveEnvelopes.

Codex MCP registration sample after `npm ci` and `npm run build` (fill in local absolute paths):

```toml
[mcp_servers.realmz-testing]
command = "node"
args = ["C:/path/to/Realmz Remake 2.0/tools/runtime_testing/dist/mcp.js"]

[mcp_servers.realmz-testing.env]
REALMZ_TESTING_HOME = "C:/path/to/local/runtime-testing-home"
```

Portable generic MCP registration sample:

```json
{
  "mcpServers": {
    "realmz-testing": {
      "command": "node",
      "args": ["C:/path/to/Realmz Remake 2.0/tools/runtime_testing/dist/mcp.js"],
      "env": { "REALMZ_TESTING_HOME": "C:/path/to/local/runtime-testing-home" }
    }
  }
}
```

## Dependency evidence

The package pins `@modelcontextprotocol/server` and `@modelcontextprotocol/client` `2.0.0`, `zod` `4.6.1`, `typescript` `7.0.2`, `tsx` `4.23.13`, and `@types/node` `22.20.2` in `package.json` and `package-lock.json`. The MCP server uses the official v2 imports documented at <https://ts.sdk.modelcontextprotocol.io/v2/>: `McpServer` from `@modelcontextprotocol/server`, `serveStdio` from `@modelcontextprotocol/server/stdio`, and Zod v4 from `zod/v4`. The opt-in `test/rendered-fixture.e2e.test.ts` launches the compiled `dist/mcp.js` through the official `Client` and `StdioClientTransport` imports and exercises a fresh native rendered fixture; set `REALMZ_TESTING_RENDERED_E2E=1` plus the three explicit fixture environment paths to run it.

Supported engine commands are `describe`, `observe`, `checkpoint`, `capture`, `restore`, `act`, `respond`, `ui`, `invoke`, and `close`. Fixture lifecycle operations are narrow and explicit; unsupported future fixture names return an explicit error.

## Journeys and evidence

`journey-start --spec JSON` and the `realmz_journey` MCP tool create persistent jobs beneath `<REALMZ_TESTING_HOME>/jobs/<job-id>`. The worker is detached from the CLI/MCP client, so `journey-status --job ID` and `journey-cancel --job ID` continue to work across client processes. A strict journey contains a name, isolated fixture session, and steps with one of `act`, `respond`, `ui`, or `invoke`, exact params, an explicit expected interaction kind, and optional capture. Defaults are 200 actions and 120 seconds; explicit limits are bounded at 10,000 actions and one hour.

Each job retains its original baseline checkpoint, accepted input sequence, complete before/after observations, trace deltas, wire errors, readiness failures, and captures in `evidence.json`. Readiness is semantic: journeys wait for a ready fixture, no presentation or host interaction, the required exploration or pending-response boundary, and the supplied visible UI control. `$pending` is accepted only as `params.response.requestId` and resolves to the exact observed pending request identity. A UI recipe may supply `{ "action": "click", "controlLabel": "Shop" }`; exactly one enabled current label must match, and evidence retains both the requested selector and the resolved engine control ID. Journeys never restore or reseed between steps. Failed jobs and their artifacts are retained; failures receive a screenshot or an explicit reason why it was unavailable, including failures before any input was submitted. The 256 MiB inclusive checkpoint-plus-JSON-plus-PNG bound reserves capacity before another action or capture.

`compare --left PATH --right PATH` and `realmz_compare` report the first difference across named gameplay semantics. Capture binaries, paths, request IDs, revisions, timing, and build metadata are ignored; initial equivalence must be proven from the saved baselines before a run can be reported equal. Same-engine Rebuilt runs compare the full saved baseline, including RNG and scenario state. Native comparison is limited to the provenance-pinned Griloch profile documented in `docs/runtime-testing.md`; an unknown profile or missing state is an explicit non-equal result. Movement and Shop now match the observed native RNG sequence; the Done recipe's control-ID versus label mismatch remains an explicit input difference, not full cross-engine equality.
