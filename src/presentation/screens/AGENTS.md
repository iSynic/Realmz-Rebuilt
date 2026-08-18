# Purpose

- Own scene-backed workspace and roster surfaces used by the canonical Classic-wide shell.

# Ownership

- Each route owns a registered scene. Scenes own durable header/layout, scrolling, and focus containment; `ClassicScreenRouter` supplies detached view content and route transitions.
- `ClassicPartyRoster` owns the persistent six-slot right rail and presentation-only character selection. A typed `CHARACTER_SELECTION` request switches that rail into Castle's countdown picker: the cursor shows picks remaining, portraits receive descending numbers, repeated clicks renumber locally, and the exact count emits one Party-ordered response without opening the Character workspace. The request is mandatory under `FD-SCENARIO-002`: the picker exposes no cancel control and Back or Escape leaves the blocking request pending.
- During memorized combat spell selection, `ClassicPartyRoster` temporarily becomes the spellbook rail. It owns only level/spell/power selection and returns the exact request-owned `CastOption`; closing or resolving the interaction restores the current detached party view. Cast/Aim and Back live in a fixed footer outside the spell list's scroll region so both actions remain visible in the canonical 1280x720 composition and the optional 800x600 Classic mode.

# Local Contracts

- Workspaces are designed for the canonical 1280x720 composition and remain reachable in the optional 800x600 Classic composition through deliberate compact reflow or scrolling. The 4:3 mode keeps a square gameplay viewport. Intermediate sizes are fallback reflows, not additional design targets; headers stack rather than clip.
- Screens present only detached `GameView` facts and explicit action availability.
- Inventory selects one party member and one exact carried item before presenting actions. Trade recipient rows, Cast Identify's source-selected caster/spell identity, and every disabled explanation come from the detached item action view; the workspace cannot expose scenario-owned opcode-36 escrow as a player stash.
- Inventory inspection renders `ItemView` facts, properties, restrictions, and a fixed action dock whose disabled controls expose source-owned reasons. Trade expands an item-local recipient row. It never reconstructs identified or curse-decoy facts from package content.
- Shop interactions show total payable gold, identified stock, player-knowable carried-item names, exact buy/sell offers, and paid identification. They submit stable stock/character/instance identities and render typed disabled reasons; they do not calculate prices, acceptance, equipment legality, or affordability.
- The Services workspace always exposes ordinary money management after party setup, even when no location service is active. It selects one detached party member and renders all three denomination transfers without deriving balance, increment, or capacity rules.
- Newly mounted route screens begin at the top after keyboard focus is restored; same-route rerenders restore their prior offset only after focus restoration, and scroll state must not leak across workspaces.
- Exploration and Combat share the shell's spatial stage rather than mounting explanatory body cards. Combat controls stay in the bottom interaction region so the actor-centered battlefield and persistent roster remain visible.
- The Character workspace uses `ClassicCharacterSheet` for presentation-owned portrait-backed character and tab selection. It renders detached overview, conditions/saves, source-backed equipment icons, abilities, spells, race/class/aging, and lifetime-record availability without emitting gameplay mutations or inventing missing prestige history. Party Order is a secondary expandable editor rather than the route's default dominant content.
- The Allies workspace owns a separately backed current-ally list and detail pane. It renders current stamina, spell points, conditions, source identity, and exact CICN media from detached views, with an explicit empty state and no mutation path. It suppresses generic route helper copy, keeps the list and record side by side at 1280x720, and deliberately stacks them at 800x600 rather than compressing fact labels into unreadable columns.
- Party setup and vault revision inspection reuse that same complete sheet. Setup inspection is a full-stage child surface with an explicit Back action; vault inspection retains the selected revision's eligibility reasons and cannot apply appearance changes.
- Its Appearance tab previews package-backed portraits and tactical icons independently. Apply emits the exact character, role, and appearance IDs; Discard resets local state and never publishes to the character vault.
- `PlayerMapPresenter` and `PlayerMapCanvas` consume only detached `PlayerMapView` plus package media. They may render exact PICT/TEXT assets, topology crop cells, markers, note, and current-party marker eligibility, but they never acquire a map, query mutable topology, or answer simulation questions. The Maps/Notes selector preserves source slots and disables unavailable entries instead of hiding them.

# Work Guidance

- Prefer reusable typed scenes for durable layout structure and keep gameplay mutation outside this subtree.

# Verification

- Run `tools/verify.ps1` and the presentation fixture gallery.

# Child DOX Index
