# Classic UI asset tooling contract

## Purpose

Own deterministic import and derivation of Realmz Rebuilt application chrome and integrated Classic media.

## Ownership

- The exact-commit Remake bitmap-control and Castle resource-fork map-marker catalog and importer.
- The complete app-owned Classic `snd ` catalog plus selected source-backed battle `cicn` families decoded from the pinned Castle `The Family Jewels` resource fork.
- Deterministic selected-surface preservation, seamless runtime tile derivation, and tiled nine-patch derivation.

## Local Contracts

- Import only entries listed in `catalog.json`, from the recorded commit, through Git object data rather than a source checkout's working files. Remake controls copy exact PNG bytes. Castle CICNs are decoded from the pinned owning resource fork by resource type and ID, with both resource-fork and output hashes validated. Each entry may override its semantic evidence label, repository, commit, path, note, and classification without weakening byte provenance.
- The source checkout is read-only and supplied explicitly by the caller; never commit a machine-specific source path.
- Preserve imported pixels byte-for-byte. Derived slate surfaces must identify their source asset and algorithm.
- Integrated media keeps exact Classic `(resource type, ID)` identity and provenance. The runtime resolves scenario package media before these application fallbacks, matching Castle's resource-chain precedence.
- Preserve existing Godot `.import` sidecars for retained catalog assets so exact-byte regeneration does not churn stable resource UIDs; newly added assets receive their sidecars from the ordinary Godot import pass.
- `build-classic-surfaces.ps1 -RebuildFromCommittedSurface` is the offline path for regenerating the seamless tile and frame kit without replacing selected SpriteCook provenance.
- Validate hashes and PNG dimensions before replacing committed outputs.

## Work Guidance

- PowerShell scripts resolve the repository root from their own location and fail on the first error.

## Verification

- `sync-classic-ui-assets.ps1` verifies source commits, source hashes, decoded CICN identity, PNG bytes, dimensions, and manifest output.
- `build-classic-surfaces.ps1` verifies every generated PNG, records deterministic SHA-256 values, and produces a tile with exact matching opposite edges.
- `verify-classic-application-media.ps1` verifies unique IDs/resource keys, the expected integrated sound and combat-CIcon counts, native image dimensions, and every committed byte count and SHA-256 without requiring an external Castle checkout.

## Child DOX Index

- No child AGENTS.md files are currently required.
