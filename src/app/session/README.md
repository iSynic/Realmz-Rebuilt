# Application session hosting

This folder is the bridge between the Godot host and one pure `GameSession`. Start with `game_session_controller.gd` to trace a committed command and detached `GameView`; start with `application_adventure_storage_host.gd` for save/restore; start with `application_character_files_host.gd` for reusable characters; and start with `application_combat_policy.gd` for host-side combat and Auto translation.

Repository-facing controllers return detached values and never mutate presentation directly. Restore constructs and validates a replacement before the controller swaps sessions. Character Files use stable identity plus revision hash, and any vault mutation invalidates the revision cache. The owning evidence spans `tests/integration/test_session_persistence.gd`, the save and Character Files infrastructure suites, and `tests/presentation/test_classic_ui_system.gd`.
