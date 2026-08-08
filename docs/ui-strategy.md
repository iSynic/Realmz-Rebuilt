# Realmz 2 Classic-wide interface strategy

Realmz 2 uses one responsive visual language whose first-screen composition is recognizably Classic Realmz: a dominant map or picture stage, a persistent six-character roster on the right, a narrative/status well along the bottom, a contextual command deck, and a compact menu strip. It does not use a dashboard title bar, route tabs, generic card grid, or permanent Chronicle inspector.

## Visual language and provenance

- The stage and content art remain dominant. Black content wells sit inside quiet charcoal slate, neutral gray frames, Classic yellow headings, restrained cyan facts, red warnings, and bright external focus rings.
- Original bitmap controls keep their exact pixels and embedded lettering. They render only at 1x or 2x with nearest-neighbor filtering. Hover, focus, pressed, and disabled states are external frames or overlays; source pixels are never repainted.
- `ClassicUiAssetCatalog` resolves the committed control corpus. `src/presentation/assets/classic-ui-assets.json` records semantic ID, exact Remake commit and path, native dimensions, SHA-256, scene-use evidence, and scaling rules. Scene use at Remake commit `86cf2bf391ef0c43ba31c1633ddd63b7e67e3d61` proves semantic purpose; the manifest does not claim direct extraction from a Classic resource fork.
- The selected surface is SpriteCook asset `3f355030-0f8c-4d4e-b079-26ba8d3dbc32`, labelled `Realmz 2 Classic-wide charcoal slate`. `tools/ui-assets/build-classic-surfaces.ps1` derives the production 512-pixel surface and matching raised/inset nine-patches; the manifest records the source SHA-256 prefix and deterministic algorithm. Rejected candidates remain outside the repository.
- Alegreya supplies narrative and headings. Alegreya Sans supplies menus, statistics, and controls. The pinned Google Fonts commit, hashes, and OFL licenses live under `src/presentation/assets/fonts/`; the runtime makes no network request.
- Classic CICNs, ICONs, PICTs, portraits, map atlases, and scenario media remain immutable package content. The app-owned bitmap-control corpus is separate from package media.

## Responsive composition

The project uses a 960x600 baseline and an 800x600 minimum. `UiLayoutProfile` selects a profile from effective width after interface density. Text scale remains independent.

| Profile | Effective width | Roster | Bottom region | Navigation |
| --- | ---: | ---: | ---: | --- |
| Compact | 800-959 | 208 logical px | 156 logical px | One `Realmz` menu; command groups wrap/scroll |
| Standard | 960-1279 | 256 logical px | 176 logical px | Full Classic menu strip |
| Wide | 1280+ | 288 logical px | 190 logical px | Full strip; extra width goes to stage/workspace |

Original controls remain 1x below 1600x900. At 1600x900 or larger, Auto or 150% density may select exact 2x art when commands remain reachable. Map tiles and package art retain their own native/integer scaling and never follow interface density fractionally. At large text/density settings, headers stack, facts wrap, and panes scroll rather than clip.

## Menu and command ownership

The top menu is the sole global navigation surface:

- `Info`: about, package identity/readiness, diagnostics.
- `Game`: campaigns, save, load, return to selection, quit.
- `Adventure`: Explore plus available adventure operations.
- `Character`: Characters, Inventory, Spells, Vault.
- `Bestiary` and `Allies`: disabled with a reason until their detached views contain sufficient facts.
- `Maps / Notes`: Journal and acquired maps.
- `Preferences`: display, audio, accessibility, and diagnostics.

Services and Battle open from typed session context, not as ordinary global destinations. `ClassicCommandCatalog` is the single registry for command ID, bitmap asset, input action, valid contexts, availability key, tooltip, accelerator, and focus order. A visible control never becomes enabled merely because art exists: `GameSession` availability remains authoritative.

## Screen composition

- Explore leaves the native map as the dominant stage. Scenario pictures temporarily occupy the stage; narration and history remain in the bottom textbox.
- Characters and Vault use compact stat/revision rows with portraits, equipment, saves, conditions, eligibility, and provenance when supplied.
- Inventory uses visible CICNs, original category and verb controls, dense item rows, and a single scroll surface. Unidentified items preserve their visible icon while exposing only player-knowable identity and details.
- Spells use original cast/abort and supporting strip art around known spells, costs, range/duration, target facts, and session-authorized casting.
- Services use typed shop, temple, bank, storage, and treasure requests. No location or operation is invented.
- Battle shows the map only when positions exist. Otherwise it presents initiative, combatants, legal actions, targets, outcomes, and an explicit tactical-movement unavailable state.
- Encounter requests remain inside the stage/textbox composition. Original Action, Items, Skills, Speak, and Stop art is used only for matching typed semantics.
- Journal and System retain modern function inside the same slate frames, dense lists, Classic hierarchy, and keyboard model.
- Campaign selection and party creation use the same material and typography while retaining responsive Race/Class and creator-stage behavior.

Every route has its own scene-backed workspace registered in `UiRouteCatalog`. The router may retain focus, selection, filter, and Back history; it cannot mutate simulation.

## Input, focus, and interaction

- Mouse and keyboard have equivalent access. Named input actions own movement, search, camp, route shortcuts, activation, cancellation, and future device bindings.
- Focus is visible and restored per route. Opening an interaction focuses the first valid response.
- Escape closes a stage picture or top interaction first, then returns through route history to Explore.
- A pending request suppresses exploration and route mutation. `InteractionPresenter` preserves request ID and exact response payload.
- Positive Classic messages use an explicit Continue response in the textbox region. Passive negative messages use the same narrative surface without fabricating a wait.

## Package media and secrecy

Package media lookup is exact by resource type plus ID, so `CICN 128`, `ICON 128`, and `PICT 128` cannot collide. Missing media produces a neutral framed fallback and diagnostic. Presentation never guesses a filename.

Detached views expose only facts needed to draw the current state. In particular, an unidentified item cannot reveal its identified name, definition identity, value, description, curse relationship, or other hidden behavior. Navigation and presentation settings never mutate simulation.

## Verification

The fixture gallery covers every route and typed interaction in nominal, empty, loading, error, unavailable, missing-media, unidentified, six-character, and oversized-content states. Required local captures cover 800x600, 960x600, 1280x720, 1600x900, and 1920x1080 plus 100-150% text/interface combinations.

Acceptance checks map dominance, roster visibility, narrative/action reachability, menu overflow, focus order/restoration, Back behavior, scrolling, exact integer art scaling, asset/font hashes, safe unidentified display, typed media collisions, and request identity. The gallery is visual evidence only; live campaign and MCP checks remain separately labelled.
