# Inventory game model

## Purpose

Own immutable item definitions and lookup, carried-item rules, wearable equipment rules, and their typed calculation results.

## Ownership

- `ItemDefinition` is the immutable authored item record resolved by every carried instance.
- `ItemInstance` is the portable mutable carried-item record stored by a character.
- `ItemCatalog` indexes the effective application-plus-scenario item definitions by stable and Classic identity.
- `InventoryRules` owns carried-item capacity, use, transfer, stack, charge, and custody admission; `InventoryActionProbe` carries a detached admission result.
- `EquipmentRules` owns wearable admission, ordered equip/unequip mutation, passive wear/remove effects, forced-removal cleanup, scroll-case presence, and combat loadout projection; `CharacterCombatEquipment` carries that projection.
- `ItemView`, `ItemFactView`, `InventoryItemActionsView`, and `ItemTransferTargetView` carry detached item presentation facts and already-calculated availability.
- `README.md` is the public maintainer entry point for item-definition resolution.

Characters retain custody of their `ItemInstance` collections while the instance type and the rules that interpret it live with the inventory feature.

## Local Contracts

- Portable `ItemInstance` values retain only a stable definition ID. Resolve that ID through the active campaign's `RealmzContent.items` catalog.
- Package assembly applies the scenario exact-ID overlay before constructing `ItemCatalog`; the catalog never implements fallback or rewrites definitions.
- Catalog results are immutable package definitions. Quantity, charges, equipped state, and custody remain playthrough state.
- `CharacterState.equipmentOrder` is the authoritative wear order. Every normal or forced removal reverses passive effects through `EquipmentRules` before `InventoryRules` may transfer or discard custody; low-level removal rejects an equipped instance.

## Work Guidance

- Add item lookup behavior to `ItemCatalog`; add item transactions to `InventoryRules` or `EquipmentRules`.
- Do not cache per-character or per-session facts in the catalog.

## Verification

- `tests/infrastructure/test_package_repository.gd` protects application-plus-scenario item composition and stable portable-item resolution.
- `tests/integration/test_inventory_session.gd` protects carried-item transactions.

## Child DOX Index

- This feature has no child DOX documents.
