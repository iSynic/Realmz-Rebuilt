# Purpose

- Own scene-backed workspace and roster surfaces used by the canonical Classic-wide shell.

# Ownership

- Each route owns a registered scene. Scenes own durable header/layout, scrolling, and focus containment; `ClassicScreenRouter` supplies detached view content and route transitions.
- `ClassicPartyRoster` owns the persistent six-slot right rail and presentation-only character selection.

# Local Contracts

- Workspaces reflow within `UiLayoutProfile` bounds and must remain reachable at 800x600 with 150 percent text. Compact headers stack rather than clip.
- Screens present only detached `GameView` facts and explicit action availability.
- Inventory selects one party member and one exact carried item before presenting actions. Trade recipient rows and every disabled explanation come from the detached item action view; the workspace cannot expose scenario-owned opcode-36 escrow as a player stash.
- Shop interactions show total payable gold, identified stock, player-knowable carried-item names, exact buy/sell offers, and paid identification. They submit stable stock/character/instance identities and render typed disabled reasons; they do not calculate prices, acceptance, equipment legality, or affordability.
- The Services workspace always exposes ordinary money management after party setup, even when no location service is active. It selects one detached party member and renders all three denomination transfers without deriving balance, increment, or capacity rules.
- Newly mounted route screens begin at the top after keyboard focus is restored; same-route rerenders restore their prior offset only after focus restoration, and scroll state must not leak across workspaces.

# Work Guidance

- Prefer reusable typed scenes for durable layout structure and keep gameplay mutation outside this subtree.

# Verification

- Run `tools/verify.ps1` and the presentation fixture gallery.

# Child DOX Index
