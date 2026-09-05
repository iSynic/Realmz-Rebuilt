# Playthrough inventory

Use `inventory_workflow.gd` for equipment, custody, Drop, Split, Join, and Trade. Use `field_item_workflow.gd` when a carried item performs Identify, Torch, a door operation, or a charged spell effect. Item definitions and portable instances remain in `src/game/inventory`; this folder coordinates their transaction through the active session.

`inventory_continuations.gd` creates typed saved continuations for item targeting and confirmation using the shared `TargetingContinuationBody` in the sibling `magic` feature. `item_xap_continuation_body.gd` retains a charged item's exact scenario-program handoff so save/restore cannot spend the charge twice or resume a different item.

Player commands enter through `intents/inventory_intents.gd`; `InventoryIntentPayloads` names the character, slot, quantity, target, and confirmation values passed to the workflow.

Begin verification with `tests/integration/test_inventory_session.gd`. Shared magic targeting is covered by the field-spell and scroll/camp suites, while `tests/integration/test_session_persistence.gd` owns interrupted item operations.
