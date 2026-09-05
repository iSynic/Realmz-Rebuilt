# Wealth, services, and treasure

This folder is the Godot-facing home of every place where the party exchanges wealth or receives loot. The ordinary Money route and the typed Shop, Temple, Bank, and Treasure tasks share one visual vocabulary, but each owns a recognizable scene and a narrow binding script.

## Where to start

- `services_screen.tscn`: route frame for ordinary Party Wealth.
- `services_workspace.tscn`: pool, adventurer ledger, exchange, location-service panel, and persistent Done action.
- `services_screen_controller.gd`: detached wealth binding and typed route commands.
- `shop_interaction.tscn`: Shop stock/pack exchange and compact alternative.
- `temple_interaction.tscn`: character and service selection with purchase actions.
- `bank_interaction.tscn`: bank account, party pool, and personal denomination transfers.
- `treasure_distribution_interaction.tscn`: loot field, recipients, item inspection, wealth, lore, and completion confirmation.

The neighboring row, chip, button, and cell scenes define repeated records. Parent scenes export them as `PackedScene` properties so visual changes stay discoverable in Godot.

## Data flow

```text
GameSession -> detached money view or typed service request
            -> route controller / interaction binder
            -> authored workspace + exported record scenes
            -> typed intent or InteractionResponse
```

Selection, filters, hover, drag previews, compact tabs, and confirmation visibility are presentation state. Prices, effects, capacity, legality, and mutation remain in game and playthrough code.

## Invariants

- Every action carries stable source identities and supplied availability.
- UI never recomputes prices, load, service results, denomination rules, or recipient eligibility.
- Unidentified and unavailable records expose only the public facts and exact reasons supplied to them.
- Treasure completion remains layered over the retained ordinary workspace.
- Wide and Compact layouts expose the same required actions without relying on an outer-page scroll.

## Performance

Each route or interaction is instantiated only at its navigation/request boundary. Repeated rows are rebound or replaced within exported collection hosts; selection and hover do not rebuild the complete workspace. Treasure animation is presentation-local and never delays the committed session result.

## Tests and preview

Realmz Builder covers the major service scenes in Wide, Compact, empty, long-content, unavailable, and error states. Money, Inventory, reward/scenario, Classic UI system, and Builder preview suites exercise the public boundaries; `tools/verify.ps1` is the aggregate gate.
