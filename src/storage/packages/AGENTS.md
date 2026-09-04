# Package storage contract

## Purpose

Install, discover, decode, validate, cache, and release immutable Providence packages without leaking transport dictionaries into runtime domains.

## Ownership

- Manifest discovery and installed-revision selection.
- ZIP inventory, integrity, canonical JSON, and package-hash verification.
- Strict schema-v3 domain decoding and cross-reference validation.
- Exact Classic media-key validation and resolution.
- Durable installation receipts, the bounded active/candidate package graph cache, and disposable parsed-document sidecars for trusted installed revisions.
- `README.md` is the public maintainer entry point for package discovery, assembly, decoder ownership, and performance-sensitive loading.

## Local Contracts

- `PackageDomainAssembler` coordinates typed package construction through public decoder and validator operations. `PackageContentDecoder` is the stable record-family entry point over `PackageStoryContentDecoder`, `PackageCharacterContentDecoder`, and `PackageEncounterContentDecoder`. `PackageWorldDecoder` exposes world-family `decode_*` operations, `PackageScenarioDecoder.decode_scenario` owns scenario construction, and cross-reference/media validation uses named public validation or resolution methods; package collaborators must not call one another's private helpers.
- `PackageCharacterContentDecoder` converts Providence's flat Caste record into `CasteDefinition` plus its named attribute and progression definitions after strict validation. The package wire fields and source arrays remain unchanged; the typed game model never receives the transport dictionary.

- Providence schema v3 is the only accepted package contract: manifest format version 2, document schema version 3, and mirrored schema SHA-256 `05ced7b000683f53e6220b9ac8f7d41c801e7e2c78c874287c2ae694b585273d`.
- Package decoding requires the pinned application definition catalog before campaign assembly, checks matching `rulesVersion`, and applies scenario definitions as exact-ID overlays before reference validation. Portable item instances retain stable definition IDs and therefore resolve through the active composed catalog. It never treats duplicated campaign data as the authority for unoverridden stock definitions, text, or media.
- External packages receive complete integrity, semantic, topology, media, and cross-reference validation before installation. Before cross-reference validation, assembly materializes an immutable empty `MessageDefinition` only for a missing direct Simple/Complex Encounter prompt ID: Castle preloads an empty string and leaves it in place when its unchecked `Data SD2` read misses. Item-specific race/caste ID `-32768` is the other narrow source sentinel: Castle resolves no display name and no character can match it, so the typed unresolved identity remains an unmatchable use restriction; arbitrary missing identities still reject. Missing scenario-text opcodes, battle messages, result programs, and every other unresolved reference also reject. A valid app-owned receipt permits later startup to validate cheap file metadata and manifest identity without repeating compiler-level semantic validation. An installed revision may restore its four primitive-only decoded documents from a Zstd sidecar tied to the receipt's exact archive SHA-256, schema hash, decoder version, payload size, and payload SHA-256. The sidecar never replaces manifest/header/domain validation and never deserializes objects; absence, mismatch, or corruption forces one complete archive SHA-256 before reparsing the immutable archive and replacing the sidecar atomically.
- Castle-distributed bundled campaigns remain ordinary untrusted scenario inputs. Manifest-only discovery may advertise them from `res://`, but first Play performs the same complete validation and immutable `user://packages` installation as any external package. Only the separately pinned stock Character Files application library uses the bundled-identity load shortcut.
- Strict scenario cross-reference validation resolves opcode 62's exact signed scenario `TEXT` resource; provenance-pinned bundled Classic packages also retain the same-ID `styl` companion and preserve one decoded character position per source text byte so every 20-byte style record still addresses its authored character. Providence removes the isolated City of Bywater source row that requests nonexistent `TEXT` 0. Opcode 67 resolves its Classic item plus both possible destinations, opcodes 72/75/78 resolve reachable destinations, and opcode 85 resolves every identity in its bounded inclusive random range. Validation also resolves opcode 57's land-level/landlook pair, opcode 92's arbitrary map/rectangle pair after Castle's map-zero/slot-zero fallback normalization, and opcode 44's result 1–4 operand plus Complex Encounter-result owner. XAP zero retains its source no-branch meaning; every other XAP, Simple Encounter, Complex Encounter, and optional opcode-85 message must exist before installation can succeed.
- Random-region battle validation follows Castle's signed battle identity: zero disables battle, negative selections resolve the absolute battle record and force bad surprise, and inverted ranges retain the serialized Classic range calculation.
- Strict scenario cross-reference validation rejects every nonzero Thief Encounter trap spell whose Classic identity is absent from the composed application/scenario spell catalog.
- Classic instructions carry exactly five Extra Code operands except opcode 92, whose compiler-preserved consecutive second row carries ten. Every compiled map retains all twenty fixed random-rectangle identities, including dormant all-zero slots that authored mutation opcodes may activate later.
- Random-rectangle battle ranges remain signed authored endpoints. Cross-reference validation derives Castle's selectable identities through the shared signed-short RNG bounds, so an inverted range is accepted only when every battle Castle can actually choose resolves; the package record is never reordered or rewritten.
- Strict decoding requires each monster's independent Classic name ID, authored bestiary description, and menu-exclusion flag; each map's nullable base scale; each occupied shop record's unique native slot; the compact cell forest bit; and every media asset's nullable scenario-music slot. Scenario music slots are unique 1–3 audio assets, and only opcode 92 may carry the compiler-preserved second five-operand row.
- The effective application-plus-scenario Race and Caste catalogs must each contain all 30 functional Classic records. Any nonempty local table that is semantically empty is rejected before overlay; an omitted local table inherits the application catalog.
- `PackageRepository` coordinates explicit collaborators. It does not construct domain records, retain unbounded package graphs, or grant external files trusted cache status.
- The graph cache retains at most the active package and one candidate. Promotion and close release obsolete graphs explicitly.
- Last-campaign prewarming uses the ordinary install worker and repository path after manifest-only discovery resolves the stable campaign identity. The host may retain one prepared candidate, claim a matching selection without reopening it, or cancel/supersede it for a different foreground selection; receipt, integrity, schema, immutable-install, and graph-cache rules are identical to ordinary selection.
- Validation errors are detached strings/results suitable for readiness UI. No collaborator accesses Nodes, presenters, sessions, or mutable gameplay state.

## Work Guidance

- Keep JSON dictionaries inside archive, codec, and validator collaborators. Return typed package results and content to callers.
- Reject unknown fields, versions, capabilities, duplicate identities, and unresolved references; do not recover through v1/v2 aliases or defaults.
- Test public installation, discovery, receipt, cache, and rejection behavior. Do not test private repository helpers.

## Verification

- `tests/storage/test_package_repository.gd` owns package trust, contract, installation, receipt, bounded graph-cache behavior, and parsed-document cache fallback/identity behavior.
- `tests/storage/test_package_install_task.gd` owns worker progress, cancellation, result handoff, shutdown behavior, and the host's bounded prewarm claim/supersession/failure-retry lifecycle.
- `tools/verify.ps1` verifies the schema mirror, synthetic fixture provenance, architecture boundaries, and the full typed suite.

## Child DOX Index

- No child AGENTS.md files are currently required.
