# Application platform

Use this folder for behavior owned by the Godot process rather than the Realmz simulation. `application_lifecycle_host.gd` handles Quit, End Adventure, and Save and Quit; `application_lifecycle.gd` holds the testable decision policy. `application_settings_controller.gd` binds presentation preferences, and `debug_tools_host.gd` translates debug-only tools into typed commands.

Lifecycle cancellation must leave the process and playthrough untouched. Presentation settings never enter deterministic state or adventure saves, and debug facilities must remain absent from release UI. Begin with `tests/presentation/test_classic_ui_system.gd`, the settings repository tests, and native startup smoke checks.
