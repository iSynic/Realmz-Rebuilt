# Purpose

- Own typed, focusable presentation components for serializable `InteractionRequest` kinds.

# Ownership

- Components translate an existing request payload into controls and emit the exact response payload selected by the player.
- `TextChoiceInteraction` may add `Take note` to a journal-eligible Classic acknowledgement and emits only `{ "takeNote": true }`; ordinary Continue remains an empty acknowledgement, and an already-recorded message exposes no duplicate mutation.
- `InteractionPresenter` owns request identity, modal visibility, and construction of `InteractionResponse`.
- `LifecycleInteraction` renders only the host-supplied End Adventure operations and emits one declared action identity. It does not save, close a session, infer combat state, or reuse scenario-choice semantics.
- `AgeUpdateInteraction` presents the source-backed band/range and nonzero fifteen-column age changes and emits only the empty `age_update` acknowledgement payload.
- `PlayerMapInteraction` owns the negative-opcode immediate display stage. It renders the detached player-map payload through the same presenter used by Maps/Notes and emits only the empty acknowledgement for the matching request ID; closing it cannot mutate acquisition state or bypass the issuing VM frame.
- `TreasureDistributionInteraction` owns `fumbled-item-recovery`, `ordinary`, and `completion-confirmation`. Fumble mode emits only exact-instance assign/leave payloads. Ordinary mode renders pending item/knowledge, pooled wealth, legal recipients and reasons, Pool/Share, exact denomination transfers, Detect/Identify caster choices, and Done. Completion mode explicitly confirms or cancels abandonment.
- `LevelUpInteraction` owns `result` and `spell-selection`. It acknowledges the exact character result or returns one validated set of stable spell IDs; it never rolls, applies gains, computes eligibility, or changes character state.
- `TempleInteraction` renders one detached selected character, the first five supplied conditions, all supplied source-priced services, and Pool/Share/Leave controls. It may disable a service only from supplied pooled-plus-personal affordability and emits only stable character/service identity or the named wealth action.
- `BankInteraction` renders only supplied pooled, banked, personal, load, Pool/Share, exact-increment, selection, and unavailable-reason facts for `BANK` and `POOLED_WEALTH_DEPARTURE`. It emits Pool, Share, one stable character/denomination transfer, or Done. It never performs bank import/return, clears a pool, resumes movement, recomputes capacity, or turns Done into a deposit.
- `BattleInteraction` consumes the request's weapon mode, rules-owned melee/projectile targets, legal-action list, typed Escape availability, eight precomputed movement options, core-proven spell/power/target/cost combinations, and source-probed charged-item/power/target combinations. Cast and item responses carry only actor, action, and stable item/spell/target identities plus spell power or selected battlefield coordinate/rotation where supplied. Automatic groups use an empty target ID plus the core-provided group label and omit individual HP. Spatial spells use the request's Data AD shape/default coordinate; the current coordinate controls are an interim functional selector until the tactical viewport owns pointer highlight and confirmation. The component never recalculates spell or item legality, masks, occupants, range, LOS, charges, or effects. Attack and movement responses remain identity-only. Disabled steps, Escape, Fire, and item use use typed reasons and cannot synthesize targets or tactical facts. Defend emits Castle's persistent Guard command, while Finish Turn is a separate response that clears Guard and remaining movement.
- The battle component is a compact bottom-region command deck, not a full-stage modal. Target, movement, item, and turn controls may wrap or scroll within that region, but they cannot cover the detached tactical viewport.

# Local Contracts

- Never add gameplay facts, targets, prices, eligibility, or service availability that are absent from the request.
- Disabled controls require a specific player-facing reason.
- Every pointer action must also be keyboard focusable.

# Work Guidance

- Keep request-kind logic in the narrowest component and preserve payload field names exactly.
- Repeated combat spells render core-supplied candidates, retain explicit addition order, permit one through `maximumTargets`, and emit that order as `targetIds`. Presentation cannot infer extra targets or reorder the selection.

# Verification

- Run `tools/verify.ps1`; interaction fixtures verify request-ID and payload preservation.

# Child DOX Index
- No child AGENTS.md files are currently required.
