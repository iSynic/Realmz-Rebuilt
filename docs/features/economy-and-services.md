# Economy and services

`EconomyRules` owns denominations, carrying weight, valuation, Pool, Share, and Swap. `TempleRules` owns the nine temple services. Shops, temples, and banks may arrive either as scenario interactions or contextual services, but their mutations converge through playthrough workflows and the public session boundary.

`EconomyIntents.money` and `EconomyIntents.service` are the player-command entry points. Their typed payloads carry only the selected operation, character, denomination, service, and amount; affordability and mutation remain in the owning workflow and rules.

`ServiceContinuations` owns the resumable service and pooled-wealth departure handoffs. `ServiceContinuationBody` carries only the active service continuation or the exact departure stage and direction; the shared saved envelope does not implement economy behavior.

Presentation renders detached prices, balances, load, and availability; it never recalculates affordability. The public regression owner is `tests/integration/test_money_workflow.gd`. Stable service layout belongs in the Services, Shop, Temple, and Bank scenes, with scripts limited to binding the supplied records.

Scenario rewards enter through `ClassicRewardOperations`. Follow terminal combat settlement and recovered fumbles into `ClassicBattleRewardBuilder`; follow Treasure assignment, Detect/Identify, level gains, and spell learning into `ClassicRewardWorkflow`. Their shared rollback and battle-message policy lives in `ClassicRewardOperationsSupport`. Reward behavior is characterized by `tests/scenario/test_reward_workflow.gd` and persistence coverage in `tests/integration/test_session_persistence.gd`.

The Shop begins at `src/ui/interaction_components/shop_interaction.tscn`. Both its wide two-ledger arrangement and compact tabbed arrangement are visible there, along with the complete transaction footer and detail wells. `shop_interaction.gd` selects one authored profile, binds request-owned values, and instantiates only `shop_item_row.tscn`, `shop_character_button.tscn`, and the explicit empty-state row for variable collections.
