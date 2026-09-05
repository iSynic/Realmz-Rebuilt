# Playthrough magic workflow contract

## Purpose

Own noncombat spell transactions, scrolls, Fast Spell bindings, typed magic targeting, and committed field-magic effects.

## Ownership

- `FieldMagicWorkflow` owns Fast Spell binding, scroll scribing/use, and learned field casting.
- `FieldMagicTargetRequestBuilder` builds the shared typed character-selection request for spells, scrolls, and magic items.
- `FieldMagicResolver` preserves target order and publishes committed field effects.
- `MagicTransitionResult` reports committed or waiting magic transitions to session coordination.
- `MagicContinuations` constructs field-spell, scroll-target, and scroll-discard continuations.
- `TargetingContinuationBody` carries the shared spell, scroll, and magic-item target or confirmation facts.

## Local Contracts

- Resolve every spell through the active application catalog plus scenario-owned exact-ID overlay.
- Use `MagicRules` and its named Classic spell-rule collaborators; do not classify spells by display name or duplicate special-ID tables.
- Spell points, charges, scroll slots, targets, effects, event order, RNG order, and age-update handoff remain transaction-owned and saveable.
- Inventory may use the shared targeting request and payload, but it owns item admission, charge spending, and item continuation kinds.
- `GameSession` alone commits, rolls back, changes revision, and constructs steps.

## Work Guidance

- Begin with `FieldMagicWorkflow` for a player field command and `FieldMagicResolver` for target/effect sequencing.
- Add immutable spell truth or calculations under `src/game/magic` or the appropriate `src/game/rules` owner.

## Verification

- `tests/integration/test_field_spell_workflow.gd` owns learned field casting and targeting.
- `tests/integration/test_scroll_camp_workflow.gd` owns scroll creation/use and Camp spell behavior.
- Inventory, persistence, combat, and presentation suites cover shared item, save, and detached-view boundaries.

## Child DOX Index
