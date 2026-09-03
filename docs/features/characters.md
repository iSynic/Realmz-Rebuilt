# Characters

Start with `CharacterState` for one adventurer's mutable truth and `CharacterRules` for creation, aging, derived statistics, and character-level legality. `CharacterView` is the detached, read-only form used by the interface. Character creation and party membership are committed through `GameSession`; UI code never edits a character directly.

Preserve stable character, race, caste, portrait, combat-icon, item-instance, and spell identities. Character Files are immutable revisions managed by storage, while an active adventure owns a detached imported copy. Tests are concentrated in the character cases of `test_realmz_rules.gd` and the public appearance and party-order workflows.

The read-only Allies and Bestiary routes share `creature_library_workspace.tscn`. That scene owns the recognizable list, detail, identity, facts, state-card, and empty-state layout; `creature_library_row.tscn` is the exported repeated record. `CreatureLibraryScreenController` selects and binds detached `MonsterView` or `MonsterCatalogEntryView` data without constructing stable controls. `test_allies_workspace.gd` verifies both routes and their compact reflow.
