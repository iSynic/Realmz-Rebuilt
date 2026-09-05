# Inventory UI

Open `inventory_screen.tscn` to edit the ordinary route. Its embedded `inventory_workspace.tscn` is the complete reusable composition used both there and when an Encounter asks the player to choose an item.

The workspace is assembled from neighboring scenes with plain responsibilities: `inventory_item_browser.tscn` owns the carried-item ledger, `inventory_command_rail.tscn` owns the selected character and item actions, `inventory_item_inspector.tscn` owns the full-width item record and Done control, and `inventory_trade_workspace.tscn` owns the two-pack transfer surface. The smaller row and panel scenes are the variable building blocks exported by those parents. `classic_item_detail_popover.tscn` is the reusable visible-facts surface shared with Shop and Treasure.

`InventoryScreenController` binds detached `GameView`, `CharacterView`, and `ItemView` values, preserves presentation-only selection and scroll state, and emits typed intents. `InventoryViewQueries` selects only from those detached values, `InventoryItemText` formats their public facts, and `InventorySceneBinding` handles repeated label, media, signal, and scroll mechanics. None of them decides gameplay legality or mutates the playthrough.

Data flows in one direction:

`GameView / ItemView -> InventoryScreenController -> authored scenes -> typed intent`

For layout work, use Realmz Builder's Wide, Compact, empty, long-content, unavailable, and error profiles. For behavior, run the Inventory session, Classic UI, shell-route, Encounter, and Builder preview suites.
