# Package infrastructure contract

## Purpose

Install, discover, decode, validate, cache, and release immutable Providence packages without leaking transport dictionaries into runtime domains.

## Ownership

- Manifest discovery and installed-revision selection.
- ZIP inventory, integrity, canonical JSON, and package-hash verification.
- Strict schema-v3 domain decoding and cross-reference validation.
- Exact Classic media-key validation and resolution.
- Durable installation receipts, the bounded active/candidate package graph cache, and disposable parsed-document sidecars for trusted installed revisions.

## Local Contracts

- Providence schema v3 is the only accepted package contract: manifest format version 2, document schema version 3, and mirrored schema SHA-256 `12376856235a11f507b993835acad87b546f87b9ad519533967ed2701ddb89cd`.
- Package decoding composes scenario-owned records with the pinned Realmz application library. It never trusts or exposes a campaign copy as the authority for stock Realmz text or media. `classic-application-spell-descriptions.json` is the current exact application-text catalog; its source commit, resource-fork hash, identity count, and runtime shape are deterministic build contracts.
- External packages receive complete integrity, semantic, topology, media, and cross-reference validation before installation. Before cross-reference validation, assembly materializes an immutable empty `MessageDefinition` only for a missing direct Simple/Complex Encounter prompt ID: Castle preloads an empty string and leaves it in place when its unchecked `Data SD2` read misses. Item-specific race/caste ID `-32768` is the other narrow source sentinel: Castle resolves no display name and no character can match it, so the typed unresolved identity remains an unmatchable use restriction; arbitrary missing identities still reject. Missing scenario-text opcodes, battle messages, result programs, and every other unresolved reference also reject. A valid app-owned receipt permits later startup to validate cheap file metadata and manifest identity without repeating compiler-level semantic validation. An installed revision may restore its four primitive-only decoded documents from a Zstd sidecar tied to the receipt's exact archive SHA-256, schema hash, decoder version, payload size, and payload SHA-256. The sidecar never replaces manifest/header/domain validation and never deserializes objects; absence, mismatch, or corruption forces one complete archive SHA-256 before reparsing the immutable archive and replacing the sidecar atomically.
- Castle-distributed bundled campaigns remain ordinary untrusted scenario inputs. Manifest-only discovery may advertise them from `res://`, but first Play performs the same complete validation and immutable `user://packages` installation as any external package. Only the separately pinned stock Character Files application library uses the bundled-identity load shortcut.
- Strict scenario cross-reference validation resolves opcode 67's Classic item plus both possible destinations, opcodes 72/75/78's reachable destinations, and every identity in opcode 85's bounded inclusive random range. It also resolves opcode 57's land-level/landlook pair, opcode 92's arbitrary map/rectangle pair, and opcode 44's result 1–4 operand plus Complex Encounter-result owner. XAP zero retains its source no-branch meaning; every other XAP, Simple Encounter, Complex Encounter, and optional opcode-85 message must exist before installation can succeed.
- Random-region battle validation follows Castle's signed battle identity: zero disables battle, negative selections resolve the absolute battle record and force bad surprise, and inverted ranges retain the serialized Classic range calculation.
- Strict scenario cross-reference validation rejects every nonzero Thief Encounter trap spell whose Classic identity is absent from the composed application/scenario spell catalog.
- Classic instructions carry exactly five Extra Code operands except opcode 92, whose compiler-preserved consecutive second row carries ten.
- Random-rectangle battle ranges remain signed authored endpoints. Cross-reference validation derives Castle's selectable identities through the shared signed-short RNG bounds, so an inverted range is accepted only when every battle Castle can actually choose resolves; the package record is never reordered or rewritten.
- Strict decoding requires each monster's independent Classic name ID, authored bestiary description, and menu-exclusion flag; each map's nullable base scale; each occupied shop record's unique native slot; the compact cell forest bit; and every media asset's nullable scenario-music slot. Scenario music slots are unique 1–3 audio assets, and only opcode 92 may carry the compiler-preserved second five-operand row.
- `PackageRepository` coordinates explicit collaborators. It does not construct domain records, retain unbounded package graphs, or grant external files trusted cache status.
- The graph cache retains at most the active package and one candidate. Promotion and close release obsolete graphs explicitly.
- Validation errors are detached strings/results suitable for readiness UI. No collaborator accesses Nodes, presenters, sessions, or mutable gameplay state.

## Work Guidance

- Keep JSON dictionaries inside archive, codec, and validator collaborators. Return typed package results and content to callers.
- Reject unknown fields, versions, capabilities, duplicate identities, and unresolved references; do not recover through v1/v2 aliases or defaults.
- Test public installation, discovery, receipt, cache, and rejection behavior. Do not test private repository helpers.

## Verification

- `tests/infrastructure/test_package_repository.gd` owns package trust, contract, installation, receipt, bounded graph-cache behavior, and parsed-document cache fallback/identity behavior.
- `tests/infrastructure/test_package_install_task.gd` owns worker progress, cancellation, result handoff, and shutdown behavior.
- `tools/verify.ps1` verifies the schema mirror, synthetic fixture provenance, architecture boundaries, and the full typed suite.

## Child DOX Index

- No child AGENTS.md files are currently required.
