# Economy and services

`EconomyRules` owns denominations, carrying weight, valuation, Pool, Share, and Swap. `TempleRules` owns the nine temple services. Shops, temples, and banks may arrive either as scenario interactions or contextual services, but their mutations converge through playthrough workflows and the public session boundary.

Presentation renders detached prices, balances, load, and availability; it never recalculates affordability. The public regression owner is `tests/integration/test_money_workflow.gd`. Stable service layout belongs in the Services, Shop, Temple, and Bank scenes, with scripts limited to binding the supplied records.
