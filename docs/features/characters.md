# Characters

Start with `CharacterState` for one adventurer's mutable truth and `CharacterRules` for creation, aging, derived statistics, and character-level legality. `CharacterView` is the detached, read-only form used by the interface. Character creation and party membership are committed through `GameSession`; UI code never edits a character directly.

`CasteDefinition` keeps identity, eligibility, equipment policy, and starting items together. Its named `AttributeDefinition` record owns save bonuses, attribute limits, starting conditions, and strength bounds; its `ProgressionDefinition` record owns stamina dice, combat growth, spellcaster rows, abilities, and victory thresholds. Providence's flat package record is unchanged, but `PackageCharacterContentDecoder` constructs these three concepts explicitly so maintainers do not have to interpret a 35-argument constructor.

`PartyIntents` is the command entry point for party assembly, Character Files import, creation drafts, starting spells, appearance, party order, and Begin Adventure. Its `PartyIntentPayloads` values retain stable character and provenance identities without embedding session state or presentation objects.

Character spell-point confirmation, Character Files publication, and source-ordered age acknowledgements resume through `ApplicationContinuations` and their typed application or age payload. They share the versioned session envelope without making character state responsible for save decoding.

Preserve stable character, race, caste, portrait, combat-icon, item-instance, and spell identities. Character Files are immutable revisions managed by storage, while an active adventure owns a detached imported copy. Tests are concentrated in the character cases of `test_realmz_rules.gd` and the public appearance and party-order workflows.

The read-only Allies and Bestiary routes share `creature_library_workspace.tscn`. That scene owns the recognizable list, detail, identity, facts, state-card, and empty-state layout; `creature_library_row.tscn` is the exported repeated record. `CreatureLibraryScreenController` selects and binds detached `MonsterView` or `MonsterCatalogEntryView` data without constructing stable controls. `test_allies_workspace.gd` verifies both routes and their compact reflow.

`classic_character_sheet.tscn` is the shared character-record surface used by the Character route, Character Files inspection, party-setup inspection, and creation review. Its persistent selector, portrait and tactical identity, tab rail, empty state, and all eight tab compositions are scene-authored. `ClassicCharacterSheet` binds detached values, switches responsive orientations, and populates only genuinely variable record hosts through exported component scenes.

`character_screen.tscn` directly contains that shared sheet plus the stable party-order summary, reorder editor, actions, and no-character state. Only one `party_order_row.tscn` instance is created per party member; the controller binds and reorders those detached records without rebuilding the route.

`vault_screen.tscn` owns the Character Files header, availability summary, empty state, current-record grid, history controls, inspection identity, eligibility notice, and embedded shared sheet. Current revisions and earlier revisions instantiate `vault_character_card.tscn` and `vault_history_row.tscn`; no stable Character Files controls are built by the controller.

`character_sheet_stat_tabs.tscn` owns the stable three-region Overview, paired Conditions/Saves, paired Modifiers/Abilities, and Lifetime Record compositions. `character_metric_row.tscn` and `character_record_card.tscn` carry variable detached values without hiding the tab hierarchy from the editor.

`character_sheet_inventory_magic_tabs.tscn` owns the Equipment and Spells compositions, including their wide/compact splits, headings, empty states, exact-item hosts, known-spell grid, and fixed scroll case. `character_item_card.tscn` and `character_spell_card.tscn` keep exact media and text structure editable while binding only detached records.

`character_sheet_identity_tabs.tscn` owns Appearance and Race, Class & Aging. It keeps independent portrait and combat-icon previews, pickers, Apply actions, and Discard action visible in the editor, and keeps authored race, caste, and five-band aging records recognizable without changing their package-backed identities.
