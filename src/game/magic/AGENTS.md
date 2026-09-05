# Magic game model

## Purpose

Own immutable spell definitions and lookup, plus the magic feature's migration boundary for its pure rules.

## Ownership

- `SpellDefinition` is the immutable authored spell record shared by every casting source.
- `SpellCatalog` indexes the effective application-plus-scenario spell definitions by stable and packed Classic identity.
- `FastSpellBindingState` and `SpellScrollState` own the mutable noncombat spell shortcuts and scroll facts stored by a playthrough.
- `README.md` is the public maintainer entry point for spell-definition resolution.

Magic rules remain under `src/game/rules` until their production files, tests, UIDs, and references move here as one coherent batch.

## Local Contracts

- `RealmzContent.magic` is the authoritative spell-definition lookup for field, combat, item, scroll, and scenario callers.
- Package assembly applies the scenario exact-ID overlay before constructing `SpellCatalog`; no casting source owns a parallel definition table.
- Learned spell IDs, Fast Spell bindings, and scroll spell IDs remain mutable playthrough facts. Catalog definitions remain immutable.

## Work Guidance

- Add definition lookup to `SpellCatalog`; add mechanics to the smallest field, combat, targeting, or effect rules owner.
- Keep Classic identity/capability rules source-backed and separate from package lookup.

## Verification

- `tests/infrastructure/test_package_repository.gd` protects spell composition and packed identity.
- Field, scroll/camp, and combat suites protect behavior after lookup.

## Child DOX Index

- This feature has no child DOX documents.
