# Realmz 2 Classic-wide interface strategy

Realmz 2 uses one responsive visual language whose first-screen composition is recognizably Classic Realmz: a dominant map or picture stage, a persistent six-character roster on the right, a narrative/status well along the bottom, a contextual command deck, and a compact menu strip. It does not use a dashboard title bar, route tabs, generic card grid, or permanent Chronicle inspector.

## Visual language and provenance

- The stage and content art remain dominant. Black content wells sit inside quiet charcoal slate, neutral gray frames, Classic yellow headings, restrained cyan facts, red warnings, and bright external focus rings.
- Original bitmap controls keep their exact pixels and embedded lettering. They render only at 1x or 2x with nearest-neighbor filtering. Hover, focus, pressed, and disabled states are external frames or overlays; source pixels are never repainted.
- A workflow action with no verified bitmap donor uses a labeled themed control. Missing catalog art must never create an unlabeled texture-button hit target or justify borrowing a semantically different marker image.
- `ClassicUiAssetCatalog` resolves the committed control corpus. `src/presentation/assets/classic-ui-assets.json` records semantic ID, owning repository/commit/path, native dimensions, SHA-256, evidence, and scaling rules. Remake scene use at commit `86cf2bf391ef0c43ba31c1633ddd63b7e67e3d61` proves command-control purpose without claiming Classic extraction. The land party markers are separately decoded from built-in CICNs 175 and 186 in Castle's pinned `The Family Jewels.rsrc`; recording the owning resource fork prevents scenario-local CICN ID collisions.
- The selected surface is SpriteCook asset `3f355030-0f8c-4d4e-b079-26ba8d3dbc32`, labelled `Realmz 2 Classic-wide charcoal slate`. `tools/ui-assets/build-classic-surfaces.ps1` preserves that production 512-pixel surface, derives a cosine-feathered 512-pixel tile whose opposite edges match exactly, and embeds the same native-scale tile in raised/inset nine-patches. Root backgrounds enable repeat sampling; panels, buttons, and frame edges use tile-axis drawing instead of stretching small center patches. The manifest records the source SHA-256 prefix and deterministic algorithm. Rejected candidates remain outside the repository.
- Alegreya supplies narrative and headings. Alegreya Sans supplies menus, statistics, and controls. The pinned Google Fonts commit, hashes, and OFL licenses live under `src/presentation/assets/fonts/`; the runtime makes no network request.
- Realmz Rebuilt ships the complete pinned integrated Classic `snd ` bank and the source-backed combat CIcon families used by current playback as versioned application media. Scenario-owned keys remain immutable package content and override the same exact application `(resource type, ID)` key. Character creation still receives detached stable appearance IDs and thumbnails from validated package media; additional built-in PICT/CICN families migrate only after their package-reference and readiness contracts are replaced deliberately. The app-owned bitmap-control and integrated-media catalogs remain provenance-checked and distinct from scenario media.

## Supported compositions

Realmz Rebuilt is designed and accepted at one canonical 16:9 resolution: 1280x720. Its default window and viewport use that composition. The only secondary composition is an optional 800x600 Classic 4:3 mode whose gameplay stage is square. `UiLayoutProfile` therefore selects either Wide or Compact; there is no separately designed intermediate profile. Other window sizes may use the nearest responsive fallback, but they do not create additional layout requirements or independent Pen designs.

| Profile | Target | Roster | Bottom region | Navigation |
| --- | ---: | ---: | ---: | --- |
| Compact | 800x600 | 208 logical px | 156 logical px | Compact Classic menu; command groups wrap/scroll |
| Wide | 1280x720 | 288 logical px | 190 logical px | Full Classic menu strip and canonical workspaces |

Text scale and interface density remain independent. Original controls use exact integer sampling; map tiles and package art never follow interface density fractionally. At larger text settings, headers stack, facts wrap, and panes scroll rather than clip. A larger host window may scale or center the canonical composition, but is smoke-tested rather than redesigned as another breakpoint.

## Menu and command ownership

The top menu is the sole global navigation surface:

- `Info`: about, package identity/readiness, diagnostics.
- `Game`: campaigns, save, load, return to selection, quit.
- `Adventure`: Explore plus available adventure operations.
- `Character`: Characters, Inventory, Spells, Vault.
- `Allies`: enabled only when the active party has held-over allies, then opens a read-only list/detail workspace from detached session state. `Bestiary` remains disabled until Providence preserves Castle's complete menu-visible monster catalog, per-record descriptions, and `notonmenu` flag; it is not a discovery log.
- `Maps / Notes`: Journal and acquired maps.
- `Preferences`: display, audio, accessibility, and diagnostics.

Services and Battle open from typed session context, not as ordinary global destinations. `ClassicCommandCatalog` is the single registry for command ID, bitmap asset, input action, valid contexts, availability key, tooltip, accelerator, and focus order. A visible control never becomes enabled merely because art exists: `GameSession` availability remains authoritative.

## Screen composition

- Explore leaves the native map as the dominant stage. Scenario pictures temporarily occupy the stage on an opaque, natively tiled stone surface that reaches beneath the complete raised bevel; narration and history remain in the bottom narrative region.
- Characters and Vault use compact stat/revision rows with portraits, equipment, saves, conditions, eligibility, and provenance when supplied. Allies uses the same route-owned composition for current held-over monster instances and never invents a persistent ally archive.
- Inventory is character-first: select a party member, then one carried record, then use the detached item details and source-probed actions. It uses visible CICNs, dense item rows, exact recipient choices for Trade, and explicit disabled reasons. Unidentified items preserve their visible icon while exposing only player-knowable identity and details. Ordinary inventory does not expose a player stash: Castle opcode 36 is scenario-owned whole-party equipment escrow, while Remake's Honest Storage is an optional donor feature rather than a Classic workflow.
- Spells use original cast/abort and supporting strip art around known spells, costs, range/duration, target facts, and session-authorized casting.
- Services use typed shop, temple, bank, and treasure requests. The shop surface shows total payable gold, identified stock, player-knowable carried-item names, core-owned prices/reasons, equipped-sale blockers, and fixed-cost identification; every action returns stable stock, character, and item-instance IDs. No location or operation is invented. A storage service may appear only if separately sourced as authored campaign behavior; it is not inferred from opcode 36 or Remake's Honest Storage.
- Battle retains the previous detached board while committed movement, attacks, projectiles, spell frames, result numbers, sounds, and defeat settlement play in event order. Controls remain masked until that cosmetic transaction settles; reduced motion collapses visuals without changing simulation. Beneath the board, one compact Classic-slate band keeps active-actor facts, an icon-backed `NOW`/`NEXT`/upcoming initiative strip, and inspected-target facts visible together. Primary and turn commands use permanent positions across two low-padding rows in the canonical combat region, leaving unavailable actions disabled in place so actor changes never reshuffle the controls. Combat casting moves memorized spell/level/power selection into the right spellbook rail; Cast/Aim and Back remain in a fixed footer while the spell list scrolls independently. Battlefield targeting then replaces the bottom status with compact Confirm and Cancel controls. The board previews supplied masks and returns the selected actor or center for one authoritative core validation. When positions do not exist, Battle presents the same initiative, combatants, legal actions, targets, outcomes, and an explicit tactical-movement unavailable state.
- Encounter requests remain inside the stage/textbox composition. Original Action, Items, Skills, Speak, and Stop art is used only for matching typed semantics.
- Journal and System retain modern function inside the same slate frames, dense lists, Classic hierarchy, and keyboard model.
- Campaign selection and party creation use the same material and typography while retaining responsive Race/Class and creator-stage behavior. Appearance browses the package's complete portrait and tactical catalogs, places the selected race's six recommendations first, and pairs matching portrait/tactical offsets until the player explicitly changes the tactical icon. The character vault is a reversible workspace with an explicit return to campaign selection or the owning party-setup surface; immutable earlier and archived revisions remain visible but cannot be imported until restored.

Every route has its own scene-backed workspace registered in `UiRouteCatalog`. The router may retain focus, selection, filter, and Back history; it cannot mutate simulation.

## Input, focus, and interaction

- Mouse and keyboard have equivalent access. Named input actions own movement, search, camp, route shortcuts, activation, cancellation, and future device bindings.
- Land maps use the complete eight-direction Classic compass: mouse regions derive horizontal and vertical movement independently, while keypad 7/9/1/3 supply diagonals and 8/6/2/4 supply cardinals. Dungeon movement remains cardinal through arrows, WASD, or keypad 8/6/2/4.
- Focus is visible and restored per route. Opening an interaction focuses the first valid response.
- Escape closes a stage picture or top interaction first, then returns through route history to Explore.
- A pending request suppresses exploration and route mutation. `InteractionPresenter` preserves request ID and exact response payload.
- Positive Classic messages use an explicit Continue response in the narrative region without a redundant "Classic Textbox" title. The interaction surface honors the assigned bottom-region bounds instead of retaining a stage-dialog minimum. Passive negative messages use the same narrative surface without fabricating a wait.
- A Classic age-band transition uses a dedicated inset `Age Update` workspace rather than the Chronicle or narrative textbox. It presents the character/race, resulting band and year range, all nonzero values from the source fifteen-column change row, and one focusable Continue response; sound 3002 is requested when each queued character becomes current.

## Package media and secrecy

Package media lookup is exact by four-character resource type plus signed ID, so `cicn 128`, `ICON 128`, and `PICT 128` cannot collide. Type case and trailing spaces remain significant. Missing or ambiguous media produces a neutral framed fallback and a developer diagnostic containing the authored key, presentation role, effective package asset ID, hash, and decoder outcome. Presentation never guesses a filename.

Detached views expose only facts needed to draw the current state. In particular, an unidentified item cannot reveal its identified name, definition identity, value, description, curse relationship, or other hidden behavior. Navigation and presentation settings never mutate simulation.

## Verification

The fixture gallery covers every route and typed interaction in nominal, empty, loading, error, unavailable, missing-media, unidentified, six-character, and oversized-content states. Required local captures cover canonical 1280x720 and optional Classic 800x600 with the supported text/interface settings. Other resolutions may receive smoke coverage but are not separate visual-acceptance targets.

Acceptance checks map dominance, roster visibility, narrative/action reachability, menu overflow, focus order/restoration, Back behavior, scrolling, exact integer art scaling, asset/font hashes, safe unidentified display, typed media collisions, and request identity. The gallery is visual evidence only; live campaign and MCP checks remain separately labelled.
