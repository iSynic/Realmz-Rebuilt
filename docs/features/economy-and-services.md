# Economy and services

`EconomyRules` owns denominations, carrying weight, valuation, Pool, Share, and Swap. `TempleRules` owns the nine temple services. Shops, temples, and banks may arrive either as scenario interactions or contextual services, but their mutations converge through playthrough workflows and the public session boundary.

Presentation renders detached prices, balances, load, and availability; it never recalculates affordability. The public regression owner is `tests/integration/test_money_workflow.gd`. Stable service layout belongs in the Services, Shop, Temple, and Bank scenes, with scripts limited to binding the supplied records.

The Shop begins at `src/ui/interaction_components/shop_interaction.tscn`. Both its wide two-ledger arrangement and compact tabbed arrangement are visible there, along with the complete transaction footer and detail wells. `shop_interaction.gd` selects one authored profile, binds request-owned values, and instantiates only `shop_item_row.tscn`, `shop_character_button.tscn`, and the explicit empty-state row for variable collections.
