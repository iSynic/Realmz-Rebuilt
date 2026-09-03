# Characters

Start with `CharacterState` for one adventurer's mutable truth and `CharacterRules` for creation, aging, derived statistics, and character-level legality. `CharacterView` is the detached, read-only form used by the interface. Character creation and party membership are committed through `GameSession`; UI code never edits a character directly.

Preserve stable character, race, caste, portrait, combat-icon, item-instance, and spell identities. Character Files are immutable revisions managed by storage, while an active adventure owns a detached imported copy. Tests are concentrated in the character cases of `test_realmz_rules.gd` and the public appearance and party-order workflows.
