# Economy and location services contract

## Purpose

Own money rules, service rules, location service state, shop state, and detached service records.

## Ownership

- `EconomyRules`, `EconomyActionProbe`, `WealthState`, and detached money views own denominations, carrying, valuation, and money transfers.
- `TempleRules` and `TempleServiceResult` own the nine Classic temple operations.
- `ShopDefinition` owns immutable authored stock.
- `TreasureDefinition` owns immutable authored wealth and item rewards.
- `EconomyContentCatalog` indexes immutable Shop and Treasure definitions for the active campaign.
- `LocationServiceState` owns current shop, temple, and bank availability plus save-owned shop quantity, inflation, buyback, and slot overrides.
- `LocationServiceStateCodec` owns the established flat service fields inside the `GameState` save dictionary.

## Local Contracts

- Scenario and playthrough callers address `GameState.location_services`; `GameState` does not forward service operations.
- Immutable `ShopDefinition` stock is never mutated. Scenario stock changes live only in `LocationServiceState`.
- Buyback quantity and native slot assignments restore together and remain deterministic.
- The codec preserves existing save keys and legacy optional-field behavior; it does not introduce a nested economy payload.

## Work Guidance

- Keep monetary calculations pure and service availability mutable.
- Add new location-service truth here instead of growing `GameState`.

## Verification

- `tests/integration/test_money_workflow.gd` owns public money and service transactions.
- `tests/integration/test_session_persistence.gd` and `tests/scenario/test_scenario_vm.gd` own save and scenario-service restoration.

## Child DOX Index

- This feature has no child DOX documents.
