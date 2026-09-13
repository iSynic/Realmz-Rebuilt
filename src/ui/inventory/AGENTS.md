# Inventory UI contract

## Purpose

- Own the editable Inventory route, its reusable Encounter workspace, item records, and two-pack Trade composition.

## Ownership

- `inventory_screen.tscn` owns the ordinary route and embeds `inventory_workspace.tscn`.
- `inventory_workspace.tscn` owns normal, alternate, empty, and Trade regions shared by the route and Encounter item selection.
- Browser, command rail, inspector, character selector, action panel, selected-item record, and Trade scenes own their stable layouts.
- `classic_item_detail_popover.tscn` and its header, label, and fact-grid components own the reusable item-detail surface used by Inventory, Shop, and Treasure; its script binds only detached visible facts.
- `InventoryScreenController` binds detached records, preserves route-local selection and scroll state, and emits typed intents. Its local Trade access binder keeps exact source, item, destination, availability, and submission wiring together without adding another intent path. Reused Encounter workspaces receive the active Wide/Compact profile on every presentation and live profile change; a sole eligible character is labelled by name, while multi-character selectors remain portrait-only.
- `InventorySceneBinding` owns repeated visual binding, signal cleanup, child cleanup, media lookup, and scroll restoration mechanics.
- `InventoryItemText` and `InventoryViewQueries` own pure display formatting and detached-view selection.

## Local Contracts

- Stable panels, headings, actions, details, empty states, and Trade regions belong in `.tscn` scenes. Variable party, item, fact, portrait, and Trade rows instantiate only exported component scenes.
- Inventory displays only detached `ItemView` facts and rules-owned availability. It never reconstructs hidden identity, curse, capacity, price, equipment, or transfer rules.
- Selecting another item preserves the current ledger scroll position; selecting another character starts that character's ledger at the top.
- Ordinary Done remains inside the lower item inspector. Trade retains fixed Money, Items, Transfer, and Done actions; Transfer commits only the currently explicit exact-item and opposite-pack destination selection.
- At 800x600, ordinary Inventory retains the horizontal browser/command split, four action columns, and a horizontal lower item record so the integrated Done remains in the initial viewport.
- Encounter item selection reuses the complete workspace, admits only request-owned character and item identities, and returns the supplied Classic identity without revealing it. A live 1280x720-to-800x600 resize reflows the retained browser, command rail, inspector, and persistent Back action without reconstructing the task.
- Trade uses two independently selected ledgers and exact-instance cross-ledger drops plus controller-accessible exact item selection followed by an explicit opposite-pack Transfer. Presentation does not preselect or infer a destination.
- Trade inspection never swaps the selected packs. Each character's Trade ledger retains its own scroll offset across inspection and transfer refreshes; occupied rows, icons, and unused ledger space all accept the same rules-checked drop.

## Work Guidance

- Edit stable composition in the owning scene and expose new variable records as exported `PackedScene` properties.
- Keep operation drafts, selection, sorting, and scroll position presentation-local. Submit all mutations through typed intents.

## Verification

- Exercise ordinary inspection, item selection with retained scroll, operation confirmation, Trade, Encounter selection, Back/Done, and Wide/Compact Realmz Builder previews.
- Run `tools/verify.ps1` before committing a workflow.

## Child DOX Index
