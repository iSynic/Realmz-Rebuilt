# Playthrough magic

Use `field_magic_workflow.gd` for Fast Spell bindings, scroll scribing and use, and learned spells cast outside combat. It coordinates the transaction against `src/game/magic` definitions and rules without owning immutable spell data or saved character truth.

`field_magic_target_request_builder.gd` creates the typed character picker shared by spells, scrolls, and magic items. `targeting_continuation_body.gd` preserves that request across save/restore, while `magic_continuations.gd` fixes the field-spell and scroll continuation kinds. Inventory reuses the payload but retains responsibility for item legality and charge spending.

`field_magic_resolver.gd` keeps party and ally targets in stable order and publishes the committed field effects. `magic_transition_result.gd` carries a completed or waiting result back to session coordination.

Player commands enter through `intents/magic_intents.gd`; `SpellIntentPayload` is the shared explicit spell command value used by field and combat casting without embedding spell definitions.

Begin verification with `tests/integration/test_field_spell_workflow.gd` and `tests/integration/test_scroll_camp_workflow.gd`; use the Inventory and session-persistence suites for magic-item and interrupted-targeting boundaries.
