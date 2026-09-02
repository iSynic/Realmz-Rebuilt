# ADR 0011: Use typed session protocols and snapshots

## Status

Accepted; implementation in progress.

## Context

`PlayerIntent`, interaction requests/responses, and session continuations accumulated unrelated fields and open dictionaries. Validation therefore depended on distant string keys, save decoding could construct partially valid state, and presentation routinely inspected core protocol dictionaries.

## Decision

Every intent kind has one typed payload. Every interaction and continuation is a closed typed variant that owns its validation and wire encoding. `GameSession` exposes a typed `SessionSnapshot`; infrastructure alone encodes and decodes save JSON. Save v4 represents variants as `{kind, version, data}` and rejects unknown kinds, versions, and fields before session construction.

## Consequences

Core workflow code receives only typed values. JSON dictionaries remain confined to package/save codecs and detached event serialization. Save versions 1 through 3 are intentionally incompatible and receive a clear host error rather than a migration.
