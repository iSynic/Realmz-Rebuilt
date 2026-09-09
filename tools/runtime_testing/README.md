# Realmz runtime testing transport

This package is the local observation/fixture transport foundation for the Realmz runtime. It provides:

- a loopback-only TCP newline-delimited JSON service with a 16 MiB request/reply limit (including the newline);
- strict Zod validation for the `realmz-testing/1` request, reply, and discovery-descriptor envelopes;
- authenticated session discovery under `REALMZ_TESTING_HOME\sessions`, with stale descriptors ignored after a live `describe` probe;
- request-ID replay protection, explicit revision checks for mutations, and service-side observe-mode mutation rejection;
- a standalone `realmz-testing` CLI and an MCP v2 stdio server exposing `realmz_sessions`, `realmz_observe`, and the initial `realmz_fixture` checkpoint operation.

The package does not launch Rebuilt or Castle and does not implement gameplay journeys. The CLI and MCP server connect to the engine's loopback endpoint; tests use a fake loopback peer under `test/support` only for transport and protocol behavior.

## Local development

```powershell
$env:REALMZ_TESTING_HOME = 'C:\path\to\local\runtime-testing-home'
npm install
npm run build
npm test
npm run mcp
```

The environment variable is intentionally required for discovery. Descriptor files contain the private session token and should stay in the local discovery root. MCP and CLI results never include that token. No global or client configuration is written by this package.

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
      "command": "npx",
      "args": ["C:/path/to/Realmz Remake 2.0/tools/runtime_testing/dist/mcp.js"],
      "env": { "REALMZ_TESTING_HOME": "C:/path/to/local/runtime-testing-home" }
    }
  }
}
```

## Dependency evidence

The package pins `@modelcontextprotocol/server` `2.0.0`, `zod` `4.6.1`, `typescript` `7.0.2`, `tsx` `4.23.13`, and `@types/node` `22.20.2` in `package.json` and `package-lock.json`. The MCP server uses the official v2 imports documented at <https://ts.sdk.modelcontextprotocol.io/v2/>: `McpServer` from `@modelcontextprotocol/server`, `serveStdio` from `@modelcontextprotocol/server/stdio`, and Zod v4 from `zod/v4`.

Supported engine commands are `describe`, `observe`, `checkpoint`, `restore`, `act`, `respond`, `ui`, `invoke`, and `close`. Only the checkpoint fixture operation is exposed through `realmz_fixture` in this initial package; unsupported future fixture names return an explicit error.
