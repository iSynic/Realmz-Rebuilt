# Saves, Character Files, and settings

Adventure saves, Character Files, and presentation settings are three separate repositories. Saves atomically preserve the complete session aggregate. Character Files store immutable character revisions and import detached copies. Settings store host presentation choices and never enter gameplay state.

Each repository validates untrusted input before replacement and uses a temporary write, readback, backup, and same-volume rename where applicable. Start in the corresponding repository under `src/storage`; use the save and character-vault suites for transactional evidence. Never solve a migration by weakening package, identity, or path validation.

Character Files presentation is owned by `src/ui/characters/vault_screen.tscn`. Its library, history, empty, and inspection regions are editor-authored; the controller binds immutable revision views into exported card and history-row scenes and never changes repository truth.
