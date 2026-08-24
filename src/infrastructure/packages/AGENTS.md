# Package infrastructure contract

## Purpose

Install, discover, decode, validate, cache, and release immutable Providence packages without leaking transport dictionaries into runtime domains.

## Ownership

- Manifest discovery and installed-revision selection.
- ZIP inventory, integrity, canonical JSON, and package-hash verification.
- Strict schema-v3 domain decoding and cross-reference validation.
- Exact Classic media-key validation and resolution.
- Durable installation receipts and the bounded active/candidate package graph cache.

## Local Contracts

- Providence schema v3 is the only accepted package contract: manifest format version 2, document schema version 3, and mirrored schema SHA-256 `6ef382e35335ba91fc72a94c4600633f68255ad30651a4da195e134887e05bdb`.
- Package decoding composes scenario-owned records with the pinned Realmz application library. It never trusts or exposes a campaign copy as the authority for stock Realmz text or media. `classic-application-spell-descriptions.json` is the current exact application-text catalog; its source commit, resource-fork hash, identity count, and runtime shape are deterministic build contracts.
- External packages receive complete integrity, semantic, topology, media, and cross-reference validation before installation. Before cross-reference validation, assembly materializes an immutable empty `MessageDefinition` only for a missing direct Simple/Complex Encounter prompt ID: Castle preloads an empty string and leaves it in place when its unchecked `Data SD2` read misses. Item-specific race/caste ID `-32768` is the other narrow source sentinel: Castle resolves no display name and no character can match it, so the typed unresolved identity remains an unmatchable use restriction; arbitrary missing identities still reject. Missing scenario-text opcodes, battle messages, result programs, and every other unresolved reference also reject. A valid app-owned receipt permits later startup to verify cheap file metadata, the complete compressed-archive SHA-256, and manifest identity without repeating compiler-level semantic validation.
- Random-rectangle battle ranges remain signed authored endpoints. Cross-reference validation derives Castle's selectable identities through the shared signed-short RNG bounds, so an inverted range is accepted only when every battle Castle can actually choose resolves; the package record is never reordered or rewritten.
- `PackageRepository` coordinates explicit collaborators. It does not construct domain records, retain unbounded package graphs, or grant external files trusted cache status.
- The graph cache retains at most the active package and one candidate. Promotion and close release obsolete graphs explicitly.
- Validation errors are detached strings/results suitable for readiness UI. No collaborator accesses Nodes, presenters, sessions, or mutable gameplay state.

## Work Guidance

- Keep JSON dictionaries inside archive, codec, and validator collaborators. Return typed package results and content to callers.
- Reject unknown fields, versions, capabilities, duplicate identities, and unresolved references; do not recover through v1/v2 aliases or defaults.
- Test public installation, discovery, receipt, cache, and rejection behavior. Do not test private repository helpers.

## Verification

- `tests/infrastructure/test_package_repository.gd` owns package trust, contract, installation, receipt, and bounded-cache behavior.
- `tests/infrastructure/test_package_install_task.gd` owns worker progress, cancellation, result handoff, and shutdown behavior.
- `tools/verify.ps1` verifies the schema mirror, synthetic fixture provenance, architecture boundaries, and the full typed suite.

## Child DOX Index

- No child AGENTS.md files are currently required.
