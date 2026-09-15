# Magic game model

## Purpose

Own immutable spell definitions and lookup, mutable spell shortcuts and scroll facts, and the pure rules shared by field, scenario, and combat casting.

## Ownership

- `SpellDefinition` is the immutable authored spell record shared by every casting source.
- `SpellCatalog` indexes the effective application-plus-scenario spell definitions by stable and packed Classic identity.
- `FastSpellBindingState` and `SpellScrollState` own the mutable noncombat spell shortcuts and scroll facts stored by a playthrough.
- `SpellView`, `SpellScrollView`, and `FastSpellBindingView` are the detached presentation records for learned magic, scrolls, and shortcuts.
- `MagicRules` is the narrow resolution entry point. Character, monster, projectile, field/scenario, target, area, roll, classification, disposition, and special-effect collaborators own their named mechanics beside it.
- Physical projectile items admit source-backed specials 0, 7, and 49. Special 7 halves a character target's current movement after a successful monster-fired hit; Castle rebuilds monster movement at activation, so a character-fired Saphron arrow retains damage without a durable monster mutation. Special 49 replaces rolled damage with current target health plus ten after the ordinary projectile defense gate. Other specials remain explicit.
- `SpellResolution`, `GroupSpellResolution`, `RepeatedSpellResolution`, `ProjectileResolution`, `SpellTargetSelection`, and `MonsterPolymorphContext` are typed intermediate and result records used by those rules.
- `README.md` is the public maintainer entry point for spell-definition resolution.

## Local Contracts

- `RealmzContent.magic` is the authoritative spell-definition lookup for field, combat, item, scroll, and scenario callers.
- Package assembly applies the scenario exact-ID overlay before constructing `SpellCatalog`; no casting source owns a parallel definition table.
- Learned spell IDs, Fast Spell bindings, and scroll spell IDs remain mutable playthrough facts. Catalog definitions remain immutable.
- Scenario-only save adjustment and forced-affect operands use a detached `SpellDefinition` copy. They never mutate the shared catalog record or leak into a subsequent cast.
- Shaped combat areas test reflection while collecting occupied targets, before their shared duration and damage rolls. Duplicate reflected recipients collapse to one effective caster result; automatic side/whole groups and persistent-field collisions do not reflect.
- Target type zero with nonzero size is executable only for source-backed special 58 Summon. Other records are malformed: Castle's picker returns battlefield coordinates to actor-index resolution, so every casting-source disposition rejects them with the same explicit diagnostic.

## Work Guidance

- Add definition lookup to `SpellCatalog`; add mechanics to the smallest field, combat, targeting, or effect rules owner.
- Keep Classic identity/capability rules source-backed and separate from package lookup.

## Verification

- `tests/infrastructure/test_package_repository.gd` protects spell composition and packed identity.
- Field, scroll/camp, and combat suites protect behavior after lookup.

## Child DOX Index

- This feature has no child DOX documents.
