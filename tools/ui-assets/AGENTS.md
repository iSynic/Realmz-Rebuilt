# Classic UI asset tooling contract

## Purpose

Own deterministic import and derivation of Realmz 2 application chrome.

## Ownership

- The exact-commit Remake bitmap-control catalog and importer.
- Deterministic slate surface and nine-patch derivation.

## Local Contracts

- Import only files listed in `catalog.json`, from the recorded commit, through Git object data rather than a source checkout's working files.
- The source checkout is read-only and supplied explicitly by the caller; never commit a machine-specific source path.
- Preserve imported pixels byte-for-byte. Derived slate surfaces must identify their source asset and algorithm.
- Validate hashes and PNG dimensions before replacing committed outputs.

## Work Guidance

- PowerShell scripts resolve the repository root from their own location and fail on the first error.

## Verification

- `sync-classic-ui-assets.ps1` verifies source commit, bytes, dimensions, and manifest output.
- `build-classic-surfaces.ps1` verifies every generated PNG and records deterministic SHA-256 values.

## Child DOX Index

- No child AGENTS.md files are currently required.
