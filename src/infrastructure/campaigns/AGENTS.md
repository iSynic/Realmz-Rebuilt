# Bundled campaign contract

## Purpose

Own the Castle-distributed scenario packages that ship with Realmz Rebuilt.

## Ownership

- Immutable Providence package archives for the 13 scenarios distributed with Castle Realmz.
- One source, compiler, license, package-identity, byte-count, and archive-hash catalog.

## Local Contracts

- Bundled campaigns are CC BY-NC-SA 4.0 content from the pinned Castle source and are compiled by the pinned Providence revision in `castle-bundled-scenarios.provenance.json`.
- Package archives are immutable release inputs. Selecting one uses the same complete validation and user-owned immutable installation path as an external package; the bundle is not a trusted-package bypass.
- A valid user-installed revision takes precedence over its bundled campaign baseline in application discovery.
- Do not add commercial, user-owned, tutorial, test, template, duplicate-version, or otherwise non-distributed scenario content here.

## Work Guidance

- Regenerate packages through Providence from a clean pinned Castle source; never hand-edit archives.
- Update the provenance catalog and release verifier atomically with any package change.

## Verification

- `tools/verify_bundled_scenarios.ps1` checks the exact archive set, file bytes, SHA-256 values, manifest identities, and Providence compiler revision.

## Child DOX Index

- No child AGENTS.md files are currently required.
