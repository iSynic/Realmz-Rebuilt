# Playthrough characters

This folder coordinates character operations that cross a session boundary. Use `character_creation_session.gd` for the standalone creation wizard and `lifecycle_party_workflow.gd` for Character Files admission, party insertion, Begin Adventure, and age-driven lifecycle work. The pure adventurer record and calculations remain in `src/game/characters`.

Reusable-character admission is deliberately ordered: validate active-campaign definitions and load, then magic, then appearance, then duplicate identity, and only then insert one detached copy. `age_continuation_body.gd` preserves a pending age acknowledgement without moving character state or wire decoding into the UI.

Start verification with `tests/core/test_character_creation_session.gd` and the character cases in `tests/core/test_realmz_rules.gd`; use the Character Files, party-order, appearance, and session-persistence suites for cross-boundary changes.
