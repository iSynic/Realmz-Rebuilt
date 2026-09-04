# Purpose

- Own editor-authored startup, campaign-selection, party-assembly, and character-creation compositions.

# Ownership

- Scenes own stable panels, headings, scroll regions, options, and actions.
- Controllers bind detached campaign, vault, party, and draft data and populate only variable records.

# Local Contracts

- Setup scenes are full-stage application surfaces and never own simulation or repository access.
- `front_door_menu.tscn` owns the recognizable menu composition but remains outside `startup_front_door.tscn` so imported menu media cannot delay the launch card's first frame. `StartupFrontDoor` instantiates it only after that frame draws; the same scene may be mounted beneath the loaded application shell without maintaining a second composition.
- Party assembly and character creation are modes of one retained setup workspace.
- Campaign and character rows remain reusable scene instances with stable identities. The campaign selector owns authored empty, selected-summary, and package-operation states and exports its campaign row scene.
- `PartySetupWorkspace` exports the shared character-sheet scene used by setup inspection and creation review. Controllers receive that scene reference from the instantiated workspace; they must not preload the sheet through a script dependency cycle.
- `PartySetupWorkspace` also exports `character_creation_appearance_step.tscn`. The step owns both catalog strips, paging, exact-media previews, alternate states, and hidden exact-ID selectors; it exports `appearance_thumbnail_row.tscn`, whose six stable choices are rebound for each detached race/catalog row.

# Work Guidance

- Keep stable controls in scenes and expose them by unique node name.
- Preserve focus names and signal identities used by startup and presentation tests.

# Verification

- Run the startup-shell and party-setup presentation fixtures plus `tools/startup_probe.gd` after composition changes.

# Child DOX Index
