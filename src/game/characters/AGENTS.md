# Character model contract

## Purpose

Own one adventurer's mutable truth, derived character rules, detached presentation record, lifetime history, and stable save codec.

## Ownership

- `CharacterState` owns live scalar facts and fixed-size character collections.
- `EquipmentOrderState` owns the private ordered equipped-instance identities and validates them against a character inventory.
- `CharacterDraftState` owns the saveable generated candidate and creation selections retained during party setup.
- `CharacterStateCodec` alone owns the character save dictionary and strict restoration.
- `CharacterRules` owns creation, aging, derived statistics, advancement, and character-level legality. `CharacterAgingResult`, `LevelUpResult`, and `StrengthResult` are its typed calculation results.
- `PartySetupRules` owns pure difficulty and recommended-level scaling used while assembling a new party.
- `CharacterView` is the detached read-only record consumed by presentation.
- Character metric, age-band, appearance-option, spell-option, party-summary, and setup views are detached records for their named character surfaces.
- `CharacterLifetimeRecord` owns cumulative character achievements and their nested value representation.
- `PartyState` owns the ordered active adventurers and party-wide character facts.
- `RaceDefinition`, `CasteDefinition`, and `CharacterAppearanceDefinition` are the immutable authored character records.
- `CharacterCatalog` indexes those definitions, including the application appearance fallback installed for a scenario.
- `AgeUpdateRequestBody` and `LevelUpRequestBody` carry detached character decisions through the shared interaction envelope.

## Local Contracts

- Runtime code mutates a character through typed fields and collection operations; it never edits encoded dictionaries. The save, special, and ability collection properties return copies for read-only bulk inspection.
- Save, vault, draft, and clone boundaries use `CharacterStateCodec` directly. `CharacterState` does not forward codec operations; `CharacterDraftState` embeds the generated character through that codec without owning character rules.
- Encoding preserves the v5/v2 field names and exact collection order. `equipmentOrder` contains every equipped instance identity exactly once; missing, duplicate, unequipped, or unknown identities reject restoration.
- Default save and Classic-array setters retain their gameplay clamps. The codec may bypass those clamps only after strict integer validation so historical state round-trips without reinterpretation.
- `RealmzContent.characters` is the authoritative definition lookup. `PartyState` owns active membership; party admission workflows, persistence, and UI remain owned by their respective boundaries.
- Character request bodies contain only detached values and may be consumed by scenario execution, playthrough, saves, and presentation without depending on those higher boundaries.
- Character creation preserves Castle's exact draw order across attributes, the discarded seventh attribute roll, rare special bonuses, stamina, age, spellcaster setup, and requested starting-level advancement. Its named phases may reorganize calculations but may not reorder RNG or state mutation.
- Classic strength bonuses live as the explicit brawn chart in `CharacterRules`; values outside the authored entries retain the established fallback and damage remains capped by the Caste maximum.
- `CharacterView.copy_from` groups fields by identity, statistics, and immutable detached components. A new detached field must be added to the matching copy phase so cached status projections cannot silently lose it.

## Work Guidance

- Add behavior to the narrowest owner: scalar and collection facts to `CharacterState`, wear-order identity to `EquipmentOrderState`, pure calculations to `CharacterRules`, wire conversion to `CharacterStateCodec`, and display-only projection to `CharacterView`.
- Preserve stable character, race, caste, appearance, item-instance, and spell identities.

## Verification

- Core rules cover creation, aging, checks, lifetime counters, and exact character round trips.
- Vault and session-persistence suites cover immutable revisions, detached copies, legacy defaults, and transactional restoration.
- Combat performance probes cover checkpoint serialization after codec changes.

## Child DOX Index
