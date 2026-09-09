# Runtime testing bridge

The developer-only bridge exposes Rebuilt observations and validated checkpoints through an owned local MCP/CLI service in `tools/runtime_testing`. It is disabled by default and cannot be enabled in a release build. Providence's preview request remains unchanged. Godot MCP Pro remains the editor/general-inspection route.

## Access and identity

An explicitly launched debug/source runtime accepts `--realmz-testing-observe` after Godot's `--` argument separator. `REALMZ_TESTING_HOME` must name an absolute local tooling directory outside player storage. `REALMZ_TESTING_BUILD` labels the inspected build; an absent label is reported as `unversioned-source`, never inferred to be a verified commit.

This does not attach to, inject into, or restart an existing runtime. Observe-mode instances use ordinary application behavior but the bridge cannot submit inputs, restore, close, or otherwise mutate the live adventure. Checkpoint export returns the public save-v4 envelope, or `snapshot_unavailable` when no safe snapshot exists. It does not fabricate an intermediate state.

Each process creates a random session identity and 256-bit authentication secret, binds an ephemeral port on `127.0.0.1`, and publishes `sessions/<sessionId>.json` beneath the tooling directory. Keep that directory private to the local user. Descriptors are credentials; do not commit or share them. Discovery validates process identity through an authenticated request rather than trusting stale files. Ordinary results omit the token. Graceful shutdown removes only the process's own descriptor.

## Engine protocol

The transport is one UTF-8 JSON request and one JSON reply per TCP connection, each terminated by a newline and bounded to 16 MiB including the newline. No binary object decoding, arbitrary script, property mutation, or network-selected filesystem path is supported. Incremental nonblocking I/O runs on the engine's main thread; complete validated commands execute at application frame boundaries.

Requests contain exactly `protocol`, `sessionId`, `token`, `requestId`, `expectedRevision`, `command`, and `params`. The protocol is `realmz-testing/1`. `expectedRevision` is null or a nonnegative integral revision; mutations require it. The supported read commands are `describe`, `observe`, and `checkpoint`, each with an empty parameter object. Descriptors advertise actual supported capabilities; a known but unimplemented command returns an explicit error.

Replies contain exactly `protocol`, `sessionId`, `requestId`, `revision`, `ok`, `result`, and `error`. An error has `code` and `message`; a successful reply has a null error. Authorization and session identity are checked before dispatch. Reusing a request identity with identical input returns its recorded reply even after a revision change. Reusing it with different input fails. Stale requests cannot mutate. After uncertain delivery, retry only the identical request identity and payload.

The bounded retry ledger retains up to 10,000 replies within a 256 MiB reservation budget. At capacity it rejects further commands instead of forgetting a previously executed mutation. Recent observations explicitly label bounded diagnostic history; they are not a complete journey recording.

## Evidence boundaries

Ordinary gameplay must route through application commands and respect modal and playback gates. Actual UI execution must deliver input to visible controls through normal routing. Direct AP/XAP/encounter invocation uses the separate debug boundary and cannot certify movement, trigger eligibility, caller context, or one-shot semantics. Automated commands belong only to isolated fixture instances; a live checkpoint may be cloned without taking control of its source.

The initial acceptance target is Grilochs Revenge, land 0 at 8,20. Direct AP results alone cannot close that ordinary-entry report. Castle comparison must establish equivalent native fixture inputs and report unsupported capabilities or unexplained differences explicitly. Source-control-flow, integration, rendered UI, ordinary-play, and Castle-runtime evidence remain separate claims.
