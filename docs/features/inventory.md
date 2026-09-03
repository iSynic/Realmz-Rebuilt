# Inventory

`ItemDefinition` describes authored content; `ItemInstance` records the portable mutable item. The active composed application-plus-scenario catalog resolves every instance ID. `InventoryRules` owns equip, trade, load, split, join, and drop legality. The playthrough inventory workflow coordinates interactions and commits the same rules through `GameSession`.

The Inventory scene may display only detached `ItemView` facts and provided action availability. Hidden identity and curse information must not be inferred in presentation. Begin behavioral work in `tests/integration/test_inventory_session.gd`; begin layout work at `src/ui/screens/inventory_screen.tscn`.
