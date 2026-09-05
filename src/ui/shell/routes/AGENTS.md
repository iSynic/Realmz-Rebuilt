# Purpose

- Own the editor-authored route definitions that connect application navigation to shell modes and workspace scenes.

# Ownership

- Each `.tres` file owns one stable route identity, label, shortcut, presentation kind, and optional Inspector-selected workspace scene path.
- `UiRouteCatalog` owns registration and lookup; route resources do not own navigation behavior.

# Local Contracts

- Exploration and Combat are `SHELL_MODE` routes and must not reference placeholder workspace scenes.
- Every `WORKSPACE` route must name a recognizable major scene. The catalog reads route metadata without loading that scene; the route definition loads it on first use and relies on Godot's ordinary resource cache for reuse.
- Preserve route IDs because menus, tests, and saved presentation settings use them as stable identities.

# Work Guidance

- Add or change route metadata in the matching resource rather than rebuilding a dictionary in script.
- Keep route files declarative and free of runtime state.

# Verification

- Run `tools/verify_application_workflow_inventory.ps1 -Check` and the presentation suites after route changes.
- Run `tools/verify_architecture_overhaul.ps1` to enforce the shell-mode and workspace-scene boundary.

# Child DOX Index
