# Playthrough characters

This folder coordinates character operations that cross a session boundary. Use `character_creation_session.gd` for the standalone creation wizard and `lifecycle_party_workflow.gd` for Character Files admission, party insertion, Begin Adventure, and age-driven lifecycle work. The pure adventurer record and calculations remain in `src/game/characters`.

Reusable-character admission is deliberately ordered: validate active-campaign definitions and load, then magic, then appearance, then duplicate identity, and only then insert one detached copy. `character_continuations.gd` creates the distinct starting-spell, Character Files publication, and age-update handoffs; their neighboring payloads preserve only the facts each transaction needs without moving character state or wire decoding into the UI.

Player commands enter through `intents/party_intents.gd`; its neighboring payload family contains only the explicit party, character, and appearance values consumed by these workflows.

`CharacterCreationSpec` carries one creation command into the workflow. The generated candidate and party-setup selections persist in `src/game/characters/character_draft_state.gd` until finalization or cancellation. Age and level-up interactions consume the detached bodies under `src/game/characters/requests`, so their data can be followed from the pure character result through workflow resumption to presentation.

Start verification with `tests/core/test_character_creation_session.gd` and the character cases in `tests/core/test_realmz_rules.gd`; use the Character Files, party-order, appearance, and session-persistence suites for cross-boundary changes.
