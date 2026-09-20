# Playthrough inventory workflow contract

## Purpose

Own carried-item transactions and field item use above pure item definitions, instances, catalogs, and rules.

## Ownership

- `InventoryWorkflow` owns equip, unequip, trade, Drop, Split, and Join transactions.
- `FieldItemWorkflow` owns Identify, Torch, door items, and charged field spell items.
- `InventoryContinuations` constructs saveable item targeting, confirmation, and item-XAP continuations using the sibling magic feature's shared targeting payload.
- `ItemXapContinuationBody` retains the exact item-owned scenario program handoff.
- `InventoryIntents` and `InventoryIntentPayloads` define typed commands for use, equipment, custody, stacks, Drop, and Trade.

## Local Contracts

- Portable `ItemInstance` records resolve through the active application catalog plus scenario-owned exact-ID overlay.
- Item targeting shares `TargetingContinuationBody` from `src/playthrough/magic`; inventory owns the item continuation kinds while magic owns the common target and spell fields.
- Inventory and field-item mutations use `InventoryRules`, `EquipmentRules`, and shared magic resolution; they do not duplicate item legality.
- A failed, cancelled, or rejected operation leaves inventory, charges, equipment, load, clock, RNG, and session revision according to the existing transaction result.
- Item-XAP and target continuations preserve stable instance, definition, actor, program, power, and source-battle identities across save/restore.
- A newly submitted Drop validates and removes the exact unequipped instance in one transaction; the legacy Drop confirmation continuation remains readable and respondable only for saves that already contain it.
- `GameSession` alone commits, rolls back, changes revision, and constructs steps.

## Work Guidance

- Begin with `InventoryWorkflow` for custody or equipment and `FieldItemWorkflow` for activating an item in the field.
- Add portable item truth to `src/game/inventory`, not to this orchestration layer.

## Verification

- `tests/integration/test_inventory_session.gd` owns public inventory and field-item transactions.
- Field-spell, scroll/camp, session-persistence, and presentation suites cover shared target and restore boundaries.

## Child DOX Index
