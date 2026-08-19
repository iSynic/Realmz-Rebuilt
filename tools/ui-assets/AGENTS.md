# Classic UI asset tooling contract

## Purpose

Own deterministic import and derivation of Realmz Rebuilt application chrome and integrated Classic media.

## Ownership

- The exact-commit Remake bitmap-control and Castle resource-fork map-marker catalog and importer.
- The complete app-owned Classic `snd ` catalog, shared Data ID item `cicn` set and unidentified substitutes, plus selected source-backed battle `cicn` families decoded from the pinned Castle `The Family Jewels` resource fork.
- Deterministic selected-surface preservation, seamless runtime tile derivation, tiled nine-patch derivation, and alpha-cropped exploration-rail reduction.

## Local Contracts

- Import only entries listed in `catalog.json`, from the recorded commit, through Git object data rather than a source checkout's working files. Remake controls copy exact PNG bytes. Castle CICNs are decoded from the pinned owning resource fork by resource type and ID, with both resource-fork and output hashes validated. Each entry may override its semantic evidence label, repository, commit, path, note, and classification without weakening byte provenance.
- The source checkout is read-only and supplied explicitly by the caller; never commit a machine-specific source path.
- Preserve imported pixels byte-for-byte. Derived slate surfaces must identify their source asset and algorithm.
- Search keeps exact built-in CICN 128 as inactive control-state evidence and imports the licensed eight-frame Searching row from its exact donor commit for runtime matte-keyed composition. Area Search keeps generic built-in CICN 129/130 as pressed/released control-state evidence and uses the licensed non-commercial Realmz eye/label bitmap from its exact tracked donor commit. Catalog records must preserve those distinctions and the license boundary.
- Integrated media keeps exact Classic `(resource type, ID)` identity and provenance. The runtime resolves scenario package media before these application fallbacks, matching Castle's resource-chain precedence.
- Preserve existing Godot `.import` sidecars for retained catalog assets so exact-byte regeneration does not churn stable resource UIDs; newly added assets receive their sidecars from the ordinary Godot import pass.
- `build-classic-surfaces.ps1 -RebuildFromCommittedSurface` is the offline path for regenerating the seamless tile and frame kit without replacing selected SpriteCook provenance. Raised and inset frames tile the selected slate through their complete bounds; bevel corners remain opaque so controls cannot reveal unrelated parent colors.
- `build-exploration-rail.ps1` alpha-crops one explicitly selected SpriteCook source and reduces it to the manifest-recorded 48x468 production rail without inventing additional ornament.
- Validate hashes and PNG dimensions before replacing committed outputs.

## Work Guidance

- PowerShell scripts resolve the repository root from their own location and fail on the first error.

## Verification

- `sync-classic-ui-assets.ps1` verifies source commits, source hashes, decoded CICN identity, PNG bytes, dimensions, and manifest output.
- `build-classic-surfaces.ps1` verifies every generated PNG, records deterministic SHA-256 values, produces a tile with exact matching opposite edges, and records the opaque-bevel algorithm version.
- `build-exploration-rail.ps1` reports the source crop plus source/output SHA-256 values; the committed manifest records those values and production dimensions.
- `verify-classic-application-media.ps1` verifies unique IDs/resource keys, the expected integrated sound, item-CIcon, and combat-CIcon counts, generated-chrome paths/dimensions, and every committed byte count and SHA-256 without requiring an external Castle checkout.

## Child DOX Index

- No child AGENTS.md files are currently required.
