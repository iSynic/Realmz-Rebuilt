# Purpose

- Own editor-authored startup, campaign-selection, party-assembly, and character-creation compositions.

# Ownership

- Scenes own stable panels, headings, scroll regions, options, and actions.
- Controllers bind detached campaign, vault, party, and draft data and populate only variable records.

# Local Contracts

- Setup scenes are full-stage application surfaces and never own simulation or repository access.
- Party assembly and character creation are modes of one retained setup workspace.
- Campaign and character rows remain reusable scene instances with stable identities.
- `PartySetupWorkspace` exports the shared character-sheet scene used by setup inspection and creation review. Controllers receive that scene reference from the instantiated workspace; they must not preload the sheet through a script dependency cycle.

# Work Guidance

- Keep stable controls in scenes and expose them by unique node name.
- Preserve focus names and signal identities used by startup and presentation tests.

# Verification

- Run the startup-shell and party-setup presentation fixtures plus `tools/startup_probe.gd` after composition changes.

# Child DOX Index
