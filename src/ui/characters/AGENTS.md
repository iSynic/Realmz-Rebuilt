# Character UI contract

## Purpose

Own the editable Character, Allies, Bestiary, and Character Files workspaces and their shared character-record presentation.

## Ownership

- `character_screen.tscn` owns Party Order, the empty state, and the persistent shared character sheet. `CharacterScreenController` binds detached party and vault views, preserves route-local selection and drafts, and emits typed host actions without mutating game state.
- `classic_character_sheet.tscn` owns the complete eight-tab character composition. Its stat, inventory/magic, and identity tab scenes own stable layout; `ClassicCharacterSheet` coordinates selection while `CharacterSheetSceneBinding` binds detached records through exported row and card scenes.
- `creature_library_workspace.tscn` is the shared read-only Allies and Bestiary composition. `CreatureLibraryScreenController` binds detached creature records, exact media identities, empty states, and compact reflow; only the exported creature-row scene may be instantiated dynamically.
- `vault_screen.tscn` owns the Character Files list, revision history, eligibility state, and immutable inspection regions. Starter installation, archival, recovery, and persistence remain outside UI.
- `age_update_interaction.tscn` owns the editable age-transition identity, artwork, change rows, empty state, and Continue action. `AgeUpdateInteraction` binds exact typed media and emits only the age-update acknowledgement.
- `level_up_interaction.tscn` owns committed level results and mandatory spell learning. `LevelUpInteraction` binds supplied gains, application descriptions, exact spell media, source-owned point accounting, and stable spell IDs without applying character rules.
- Character, creature, party-order, vault, metric, item, spell, and record collections instantiate their exported row/card scenes. Binding scripts may not construct or replace stable screen hierarchy.

## Local Contracts

- All four routes consume detached app-owned views and stable identities; they never read repositories, package records, or mutable session state directly.
- Appearance keeps portrait and tactical-icon identities independent. Apply emits the exact role and appearance identity; Discard remains presentation-only.
- Equipment and spell tabs render supplied public facts only. They never infer hidden item data, equipment slots, spell legality, or character rules.
- Wide layout uses recognizable side-by-side records; Compact layout deliberately stacks or scrolls the same authored regions without removing actions.
- Party setup and creation review reuse the same complete character-sheet scene rather than maintaining a second layout.

## Work Guidance

- Begin visual edits in the owning `.tscn`, then adjust its binding script only for data, signals, selection, or responsive state.
- Preserve scene UIDs and update Builder preview registration, routes, tests, and guides in the same move.

## Verification

- Run the Character, Allies/Bestiary, Character Files, Classic UI system, and Realmz Builder preview suites.
- Include age-update and level-up interaction fixtures when their scenes or binders change.
- Run the architecture-overhaul and dependency verifiers after changing paths or ownership.

## Child DOX Index
