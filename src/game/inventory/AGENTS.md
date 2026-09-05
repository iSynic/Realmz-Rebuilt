# Inventory game model

## Purpose

Own immutable item definitions and lookup, plus the inventory feature's migration boundary for its pure rules.

## Ownership

- `ItemDefinition` is the immutable authored item record resolved by every carried instance.
- `ItemCatalog` indexes the effective application-plus-scenario item definitions by stable and Classic identity.
- `README.md` is the public maintainer entry point for item-definition resolution.

Inventory rules remain under `src/game/rules` until their production files, tests, UIDs, and references move here as one coherent batch. Mutable carried items remain on `CharacterState`.

## Local Contracts

- Portable `ItemInstance` values retain only a stable definition ID. Resolve that ID through the active campaign's `RealmzContent.items` catalog.
- Package assembly applies the scenario exact-ID overlay before constructing `ItemCatalog`; the catalog never implements fallback or rewrites definitions.
- Catalog results are immutable package definitions. Quantity, charges, equipped state, and custody remain playthrough state.

## Work Guidance

- Add item lookup behavior to `ItemCatalog`; add item transactions to `InventoryRules` or `EquipmentRules`.
- Do not cache per-character or per-session facts in the catalog.

## Verification

- `tests/infrastructure/test_package_repository.gd` protects application-plus-scenario item composition and stable portable-item resolution.
- `tests/integration/test_inventory_session.gd` protects carried-item transactions.

## Child DOX Index

- This feature has no child DOX documents.
