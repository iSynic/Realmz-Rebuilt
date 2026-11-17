# Playthrough save editing

This folder holds the save editor's detached draft. `save_edit_draft.gd` is the entry point: it opens over a saved `GameState`, records each change as an operation, and replays every operation from the saved state after each command, so undo, dependency checks and the experience-multiplier recalculation stay consistent. Each party member gets a `CharacterEditDraft` from `src/game/characters/editing`; call `refresh()` after editing one so the replayed state picks it up.

`save_edit_eligibility.gd` decides whether a save is at rest and explains why when it is not. `save_edit_operations.gd` applies the save-level operations and `save_edit_describer.gd` labels them for the change list.

Writing the edited save, the backup it leaves and keeping dropped characters in Character Files happen in `src/app/session/save_editor_session.gd`. Start verification with `tests/integration/test_save_editing.gd`.
