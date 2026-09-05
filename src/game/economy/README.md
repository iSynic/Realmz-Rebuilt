# Economy and location services

This feature owns the rules and mutable facts for money, shops, temples, and banks.

- `EconomyRules` calculates denomination, carrying, valuation, Pool, Share, and Swap behavior.
- `TempleRules` resolves the nine Classic temple services.
- `LocationServiceState` stores the current location's service availability and mutable shop stock.
- `LocationServiceStateCodec` preserves those facts in the established flat `GameState` save dictionary.
- `EconomyContentCatalog` resolves neighboring immutable `TreasureDefinition` and `ShopDefinition` records through `RealmzContent.economy`.
- `TreasureRoll` is the typed deterministic result produced from an immutable Treasure definition before distribution.
- `WealthState` and the detached money/service views carry the feature's mutable and presentation-facing records.
- `requests/` contains the detached Bank, service, Shop, Temple, and Treasure bodies carried by `InteractionRequest`.

Scenario operations may open a service, but they call these owners rather than maintaining a second shop, temple, bank, or wealth model. `GameState.location_services` is the live entry point. Save and restore tests protect the unchanged wire keys, while `test_money_workflow.gd` protects the public transactions.
