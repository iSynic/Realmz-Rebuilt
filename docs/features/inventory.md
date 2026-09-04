# Inventory

`ItemDefinition` describes authored content; `ItemInstance` records the portable mutable item. The active composed application-plus-scenario catalog resolves every instance ID. `InventoryRules` owns equip, trade, load, split, join, and drop legality. `InventoryWorkflow` coordinates equip, unequip, trade, Split, and Join transactions through `GameSession`; `FieldItemWorkflow` owns Identify, Torch, door items, and charged spell items rather than hiding those operations in a combined inventory-and-magic owner.

The Inventory scene may display only detached `ItemView` facts and provided action availability. Hidden identity and curse information must not be inferred in presentation. Begin behavioral work in `tests/integration/test_inventory_session.gd`; begin layout work at `src/ui/screens/inventory_screen.tscn`.

`inventory_screen.tscn` embeds the reusable `inventory_workspace.tscn` used by both the ordinary route and Encounter item selection. That workspace owns the normal browser/command/inspector split plus the alternate state host. The character summary, item actions and confirmation, selected-item record, empty state, and complete two-ledger Trade composition are neighboring editable scenes. Variable party members, item rows, facts, trade portraits, and trade items instantiate the exported component scenes; `InventoryScreenController` binds their detached identities and emits intents without constructing Controls.

Player commands enter through `InventoryIntents`: use and targeted use carry `InventoryIntentPayloads.Use` or `Target`, while equip, unequip, drop, split, join, and trade share the explicit `Action` value. The factory fixes the command kind so callers cannot accidentally pair an inventory payload with an unrelated operation.
