# Inventory definitions

Start with `ItemCatalog` when you need to resolve an item identity. Its neighboring `ItemDefinition` is the immutable authored record. A carried `ItemInstance` deliberately stores only its stable definition ID, charges, and mutable instance facts. The active campaign supplies the meaning of that ID through `RealmzContent.items`.

```text
application item definitions
          +
scenario exact-ID overlays
          |
          v
      ItemCatalog
          |
          v
ItemInstance -> InventoryRules -> detached ItemView
```

Package assembly performs the application/scenario composition once. `ItemCatalog` indexes the resulting immutable definitions by stable ID and Classic numeric ID; it does not own fallback policy or playthrough state. This keeps Character Files portable without copying a scenario definition into the character record.

The detached `ItemView` sits beside the item model it describes. `ItemFactView`, `InventoryItemActionsView`, and `ItemTransferTargetView` carry only visible facts and precomputed action availability; UI code never resolves a hidden definition or recalculates item legality.

`inventory_rules.gd` owns carried-item admission and mutation. `equipment_rules.gd` owns wearable admission and combat loadout projection; its result is `CharacterCombatEquipment`. Item transactions enter through `InventoryRules`, `EquipmentRules`, `InventoryWorkflow`, and `FieldItemWorkflow`. Begin verification with `test_package_repository.gd` for catalog composition and `test_inventory_session.gd` for gameplay.
