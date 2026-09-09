# Runtime testing transport

## Purpose

Own the local Realmz runtime-testing observation and fixture transport package: strict protocol schemas, loopback service, session discovery, MCP v2 stdio tools, CLI, and focused protocol tests.

## Ownership

- Own `realmz-testing/1` request/reply framing, the engine-facing client, and descriptor discovery under `REALMZ_TESTING_HOME`.
- Own credential handling, loopback-only connections, replay protection, and access/revision gates at this transport boundary.
- Do not own Rebuilt/Castle process launching, gameplay fixtures, ordinary-play journeys, or engine behavior.

## Local Contracts

- All requests and replies are newline-delimited JSON and limited to 16 MiB including the newline.
- Request IDs are non-empty and limited to 128 characters; a changed body under an existing ID returns `request_id_conflict`.
- Connections target `127.0.0.1` only; descriptor paths remain below the explicit discovery root.
- Discovery reads at most 256 regular, non-symlink descriptor files and rejects descriptor files over 64 KiB.
- Tokens stay in local descriptor files and authenticated internal requests; they are excluded from sanitized discovery, MCP results, and transport logs.
- Mutating commands require `expectedRevision`; observe-access sessions reject them service-side. A caller may retry an ambiguous mutation only with the same explicit `requestId`.
- MCP input and wire replies are strict Zod schemas. `realmz_fixture` exposes `checkpoint` only until future operations receive an implemented engine contract.

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
