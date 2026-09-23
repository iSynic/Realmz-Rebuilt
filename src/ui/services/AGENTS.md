# Services UI contract

## Purpose

Own the editable Party Wealth, Shop, Temple, Bank, and Treasure workspaces and their typed presentation boundaries.

## Ownership

- `services_screen.tscn` and `services_workspace.tscn` own ordinary Party Wealth: pooled/banked totals, adventurer ledger, selected-character exchange, denomination transfers, money-changing rates, location service, empty states, and fixed Done action. `ServicesScreenController` binds detached money views and rules-owned availability.
- `shop_interaction.tscn` owns the wide two-ledger and compact tabbed Shop compositions. Its script binds request-owned stock, packs, filters, offers, load, inline Pool/Share, and exact typed responses through exported record scenes. Items remains a browse-only application workspace while the Shop owns inventory mutation. Money opens the reusable Party Wealth workspace with active Pool, Share, Swap, and changing controls; these submit Shop responses, retain the pending transaction through each refresh, and return through contextual Back.
- `temple_interaction.tscn` owns adventurer, service, inspection, Pool/Share, Purchase, and Leave regions. `bank_interaction.tscn` owns account, pooled, adventurer, transfer, and departure regions. Their scripts bind only supplied facts and actions.
- `treasure_distribution_interaction.tscn` owns ordinary loot distribution, Castle's Money/Pool/Share actions, lore controls, recipient selection, item facts, recovery, and the nested completion confirmation. Personal denomination transfers live only in the Money-button workspace, never inline in Treasure; its canonical grid reserves the recipient column before wrapping loot, and its bounded command pane keeps Done fixed while excess lore controls scroll locally. `ClassicTreasureTakeEffect` is presentation-only pickup animation; `TreasureDisplayText` formats detached public summaries.
- The feature's row, chip, button, cell, and alternate-workspace scenes are the only dynamic records these owners may instantiate.

## Local Contracts

- Prices, affordability, capacity, service effects, transfer increments, item facts, recipient eligibility, and disabled reasons come from detached views or typed requests. UI never recalculates them.
- All mutations emit existing stable character, item-instance, stock, service, denomination, caster, or action identities. Dragging is an alternate presentation gesture over the same response boundary.
- Treasure retains its exact ordinary workspace beneath completion confirmation and never exposes hidden item facts.
- Treasure's scene-owned empty-field message uses the full loot width outside the item grid; previously occupied item slots still remain vacant in their original positions after assignment.
- Treasure resolves item artwork by its exact resource type and signed ID through the effective media catalog; only zero denotes an absent icon. Loot cells, inspection, and pickup effects preserve the same identity.
- Party Wealth is always available after setup; location services appear only from explicit detached availability.
- Transfer and conversion buttons activate once on press, then repeat after 350 milliseconds at 90-millisecond intervals while held. Rebinding retains their nodes and stops a hold when its action becomes unavailable or the workspace changes.
- Stable hierarchy and responsive layout belong in scenes. Selection, filtering, hover, local drafts, and request-sized records remain presentation-owned.
- Consecutive requests for the same Shop retain the selected shoppers, category, compact tab, valid inspected identity, and both ledger scroll offsets. A different Shop or intervening non-Shop task starts fresh. Item inspection and buy/sell gestures never reset an unchanged pack to the top.
- Controller focus may select exact Shop stock or carried-item rows directly; the focused row and transaction selection are one state, and both ledgers, shopper portraits, transaction actions, and contextual workspace exits remain controller-focusable.
- Consecutive requests for the same Treasure retain the loot-field scroll offset when their stable slot layout is unchanged. Taking an item leaves its authored slot vacant and never returns a scrolled loot field to the top; a different Treasure starts fresh.

## Work Guidance

- Begin layout changes in the owning workspace or interaction `.tscn`; use the neighboring exported row scenes for repeated records.
- Keep economy, inventory, service, and reward rules in game/playthrough owners. This folder may animate or format committed public results but not decide them.

## Verification

- Run the money workflow, inventory workflow, Classic UI system, and Realmz Builder preview suites.
- Run scenario/reward coverage when changing Shop, Temple, Bank, or Treasure typed interactions.

## Child DOX Index
