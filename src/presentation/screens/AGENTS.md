# Purpose

- Own scene-backed workspace and roster surfaces used by the canonical Classic-wide shell.

# Ownership

- Each route owns a registered scene. Scenes own durable header/layout, scrolling, and focus containment; `ClassicScreenRouter` supplies detached view content and route transitions.
- `ClassicPartyRoster` owns the persistent six-slot right rail and presentation-only character selection.

# Local Contracts

- Workspaces reflow within `UiLayoutProfile` bounds and must remain reachable at 800x600 with 150 percent text. Compact headers stack rather than clip.
- Screens present only detached `GameView` facts and explicit action availability.

# Work Guidance

- Prefer reusable typed scenes for durable layout structure and keep gameplay mutation outside this subtree.

# Verification

- Run `tools/verify.ps1` and the presentation fixture gallery.

# Child DOX Index
