# Purpose

- Own editor-authored startup, campaign-selection, party-assembly, and character-creation compositions.

# Ownership

- Scenes own stable panels, headings, scroll regions, options, and actions.
- `startup_front_door.tscn` owns the first-frame launch-card composition, while `ClassicIntroAnimation` owns only the retained source-backed intro presentation used by the deferred menu.
- Controllers bind detached campaign, vault, party, and draft data and populate only variable records.
- `CampaignLibraryController` binds the front door and campaign selector. `CampaignPartySetupController` composes retained campaign, party assembly, inspection, and creation collaborators around one explicit `CampaignPartySetupState`.
- `PartySetupAssemblyController` binds the reusable-character browser and retained six-slot party list; `PartySetupInspectionController` mounts the shared character sheet; `PartySetupCharacterCreationController` owns the five-step draft lifecycle.
- `PartySetupRaceCasteBinding` and `PartySetupAppearanceEditor` bind their narrow authored steps. `PartySetupControllerComponent` supplies only shared controller lifecycle, and `ClassicDefinitionToggleList` owns the exported variable definition buttons used by creation.
- `party_setup_character_row.tscn` and `party_setup_party_slot.tscn` own reusable Character Files and party-slot records; `PartySetupPartyList` coordinates only the retained record instances.

# Local Contracts

- Setup scenes are full-stage application surfaces and never own simulation or repository access.
- `front_door_menu.tscn` owns the recognizable menu composition but remains outside neighboring `startup_front_door.tscn` so imported menu media cannot delay the launch card's first frame. `StartupFrontDoor` instantiates it only after that frame draws; the same scene may be mounted beneath the loaded application shell without maintaining a second composition.
- Party assembly and character creation are modes of one retained setup workspace.
- `party_assembly_browser.tscn` owns the Character Files heading, record host, empty state, and pager; it exports the variable character-row scene. `party_setup_inspection_overlay.tscn` owns the complete Back/header/scroll composition and hosts the shared character sheet.
- Campaign and character rows remain reusable scene instances with stable identities. The campaign selector owns authored empty, selected-summary, and package-operation states and exports its campaign row scene.
- Runtime construction, editor preview, and tests bind the same existing `CampaignSelectionPanel` and `PartySetupWorkspace` instances through the public setup-controller binders; no alternate preview hierarchy is permitted.
- `PartySetupWorkspace` exports the shared character-sheet scene used by setup inspection and creation review. Controllers receive that scene reference from the instantiated workspace; they must not preload the sheet through a script dependency cycle.
- `PartySetupWorkspace` exposes all five character-creation step scenes. Appearance remains an exported `PackedScene`; the other major steps use editor-visible scene paths cached on first use so unopened creator workspaces do not join the startup dependency graph. Identity owns its preview and exact draft fields; Race/Caste owns both definition selectors and detail records; Appearance owns both catalog strips, paging, exact-media previews, alternate states, and hidden exact-ID selectors; Review owns its status and shared-sheet host; Starting Spells owns its alternate states, fixed level rail, list/detail workspace, and allowance. Appearance exports `appearance_thumbnail_row.tscn`, whose six stable choices are rebound for each detached race/catalog row; Starting Spells exports the shared spell-row and effect-preview scenes.

# Work Guidance

- Keep stable controls in scenes and expose them by unique node name.
- Open `startup_front_door.tscn` for the lightweight launch card and `front_door_menu.tscn` for the deferred interactive entry menu.
- Preserve focus names and signal identities used by startup and presentation tests.

# Verification

- Run the startup-shell and party-setup presentation fixtures plus `tools/startup_probe.gd` after composition changes.

# Child DOX Index
