# Services UI contract

## Purpose

Own the editable Party Wealth, Shop, Temple, Bank, and Treasure workspaces and their typed presentation boundaries.

## Ownership

- `services_screen.tscn` and `services_workspace.tscn` own ordinary Party Wealth: pooled/banked totals, adventurer ledger, selected-character exchange, denomination transfers, location service, empty states, and fixed Done action. `ServicesScreenController` binds detached money views and rules-owned availability.
- `shop_interaction.tscn` owns the wide two-ledger and compact tabbed Shop compositions. Its script binds request-owned stock, packs, filters, offers, load, and exact typed responses through exported record scenes.
- `temple_interaction.tscn` owns adventurer, service, inspection, Pool/Share, Purchase, and Leave regions. `bank_interaction.tscn` owns account, pooled, adventurer, transfer, and departure regions. Their scripts bind only supplied facts and actions.
- `treasure_distribution_interaction.tscn` owns ordinary loot distribution, Castle's Money/Pool/Share actions, lore controls, recipient selection, item facts, recovery, and the nested completion confirmation. Personal denomination transfers live only in the Money-button workspace, never inline in Treasure; its canonical grid reserves the recipient column before wrapping loot, and its bounded command pane keeps Done fixed while excess lore controls scroll locally. `ClassicTreasureTakeEffect` is presentation-only pickup animation; `TreasureDisplayText` formats detached public summaries.
- The feature's row, chip, button, cell, and alternate-workspace scenes are the only dynamic records these owners may instantiate.

## Local Contracts

- Prices, affordability, capacity, service effects, transfer increments, item facts, recipient eligibility, and disabled reasons come from detached views or typed requests. UI never recalculates them.
- All mutations emit existing stable character, item-instance, stock, service, denomination, caster, or action identities. Dragging is an alternate presentation gesture over the same response boundary.
- Treasure retains its exact ordinary workspace beneath completion confirmation and never exposes hidden item facts.
- Party Wealth is always available after setup; location services appear only from explicit detached availability.
- Stable hierarchy and responsive layout belong in scenes. Selection, filtering, hover, local drafts, and request-sized records remain presentation-owned.

## Work Guidance

- Begin layout changes in the owning workspace or interaction `.tscn`; use the neighboring exported row scenes for repeated records.
- Keep economy, inventory, service, and reward rules in game/playthrough owners. This folder may animate or format committed public results but not decide them.

## Verification

- Run the money workflow, inventory workflow, Classic UI system, and Realmz Builder preview suites.
- Run scenario/reward coverage when changing Shop, Temple, Bank, or Treasure typed interactions.

## Child DOX Index
