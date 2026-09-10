# Application library contract

## Purpose

Own the one Providence-built stock Realmz application package accepted by Rebuilt.

## Ownership

- `realmz-classic-application-library.realmz2` contains stock definitions and media exactly once.
- `application-library.lock.json` records the Providence catalog/compiler revisions, source and catalog hashes, schema identity, counts, and exact package identity accepted by Rebuilt.

## Local Contracts

- The package contains no scenario payload.
- Replace the package and lock together from one deterministic Providence build.
- Scenario content may override application content only through the exact definition identity or exact `(resourceType, resourceId)` required by the runtime contract.
- Rebuilt does not maintain or hand-edit the readable source catalogs; Providence owns them.
- Stock Race rules come from Castle's first 30 native 408-byte `Data Race` records. Library replacement verifies every decoded native field, reciprocal Caste eligibility, unchanged unrelated catalogs/media, and deterministic archive output before runtime acceptance.
- Exact `PICT:302` retains the complete 640x640 source image with a 20x20 grid of 32-pixel tiles. Dungeon and battle presentation derive their regions from that one resource; library replacement must preserve its native decoded pixels and leave unrelated catalogs and media unchanged.

## Work Guidance

- Verify the shared compatibility fixtures before accepting a replacement.
- Update `ApplicationLibraryIdentity`, starter-character output, release filters, and notices in the same change.

## Verification

- Run `tools/providence_alignment_probe.gd` through headless Godot.
- Run the package repository and Character Files workflow suites.

## Child DOX Index
