# Classic UI asset tooling contract

## Purpose

Own deterministic import and derivation of Realmz 2 application chrome.

## Ownership

- The exact-commit Remake bitmap-control and Classic map-marker catalog and importer.
- Deterministic selected-surface preservation, seamless runtime tile derivation, and tiled nine-patch derivation.

## Local Contracts

- Import only files listed in `catalog.json`, from the recorded commit, through Git object data rather than a source checkout's working files. Each entry may override its semantic evidence label, repository, commit, path, note, and classification without changing byte provenance.
- The source checkout is read-only and supplied explicitly by the caller; never commit a machine-specific source path.
- Preserve imported pixels byte-for-byte. Derived slate surfaces must identify their source asset and algorithm.
- Preserve existing Godot `.import` sidecars for retained catalog assets so exact-byte regeneration does not churn stable resource UIDs; newly added assets receive their sidecars from the ordinary Godot import pass.
- `build-classic-surfaces.ps1 -RebuildFromCommittedSurface` is the offline path for regenerating the seamless tile and frame kit without replacing selected SpriteCook provenance.
- Validate hashes and PNG dimensions before replacing committed outputs.

## Work Guidance

- PowerShell scripts resolve the repository root from their own location and fail on the first error.

## Verification

- `sync-classic-ui-assets.ps1` verifies source commit, bytes, dimensions, and manifest output.
- `build-classic-surfaces.ps1` verifies every generated PNG, records deterministic SHA-256 values, and produces a tile with exact matching opposite edges.

## Child DOX Index

- No child AGENTS.md files are currently required.
