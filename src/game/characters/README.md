# Characters

This folder is the starting point for the data and rules belonging to one adventurer.

- `character_state.gd` is the mutable character carried by an active playthrough.
- `character_state_codec.gd` translates that state to and from the stable save and Character Files representation.
- `character_rules.gd` contains pure creation, aging, advancement, and derived-stat calculations.
- `character_view.gd` builds the detached read-only record shown by the interface.
- `character_lifetime_record.gd` stores cumulative achievements such as battles, kills, spells, and scenario service.
- `party_state.gd` owns the ordered active party without taking over character creation or admission workflows.
- `race_definition.gd`, `caste_definition.gd`, and `character_appearance_definition.gd` are the immutable authored records.
- `character_catalog.gd` resolves those Race, Caste, portrait, and combat-icon definitions for the active campaign.

The normal flow is:

`RealmzContent.characters -> CharacterRules -> CharacterState -> CharacterView`

At a save, snapshot, draft, or Character Files boundary, `CharacterStateCodec` encodes or restores the same state without changing its stable field names or identities. UI code consumes `CharacterView`; it does not mutate `CharacterState` directly.

Begin verification with `test_realmz_rules.gd` for character behavior, `test_character_vault_repository.gd` for Character Files, and `test_session_persistence.gd` for playthrough restoration.
