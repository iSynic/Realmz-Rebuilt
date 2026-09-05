# Character model contract

## Purpose

Own one adventurer's mutable truth, derived character rules, detached presentation record, lifetime history, and stable save codec.

## Ownership

- `CharacterState` owns live scalar facts and fixed-size character collections.
- `CharacterStateCodec` alone owns the character save dictionary and strict restoration.
- `CharacterRules` owns creation, aging, derived statistics, advancement, and character-level legality.
- `CharacterView` is the detached read-only record consumed by presentation.
- `CharacterLifetimeRecord` owns cumulative character achievements and their nested value representation.
- `CharacterCatalog` indexes immutable Race, Caste, and appearance definitions, including the application appearance fallback installed for a scenario.

## Local Contracts

- Runtime code mutates a character through typed fields and collection operations; it never edits encoded dictionaries. The save, special, and ability collection properties return copies for read-only bulk inspection.
- Save, vault, draft, and clone boundaries use `CharacterStateCodec` directly. `CharacterState` does not forward codec operations.
- Encoding preserves the existing field names, defaults, collection order, and legacy optional fields exactly.
- Default save and Classic-array setters retain their gameplay clamps. The codec may bypass those clamps only after strict integer validation so historical state round-trips without reinterpretation.
- `RealmzContent.characters` is the authoritative definition lookup. Party membership, persistence, and UI remain owned by their respective boundaries.

## Work Guidance

- Add behavior to the narrowest owner: mutable facts to `CharacterState`, pure calculations to `CharacterRules`, wire conversion to `CharacterStateCodec`, and display-only projection to `CharacterView`.
- Preserve stable character, race, caste, appearance, item-instance, and spell identities.

## Verification

- Core rules cover creation, aging, checks, lifetime counters, and exact character round trips.
- Vault and session-persistence suites cover immutable revisions, detached copies, legacy defaults, and transactional restoration.
- Combat performance probes cover checkpoint serialization after codec changes.

## Child DOX Index
