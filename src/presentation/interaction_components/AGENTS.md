# Purpose

- Own typed, focusable presentation components for serializable `InteractionRequest` kinds.

# Ownership

- Components translate an existing request payload into controls and emit the exact response payload selected by the player.
- `TextChoiceInteraction` may add `Take note` to a journal-eligible Classic acknowledgement and emits only `{ "takeNote": true }`; ordinary Continue remains an empty acknowledgement, and an already-recorded message exposes no duplicate mutation.
- `InteractionPresenter` owns request identity, modal visibility, and construction of `InteractionResponse`.
- `SelectionInteraction` keeps the active character prompt in the Classic textbox while `ClassicPartyRoster` owns the numbered portrait interaction; it must not recreate a checklist or a separate Choose button. Ally body-count selection remains in its dedicated list.
- `LifecycleInteraction` renders only the host-supplied End Adventure operations and emits one declared action identity. It does not save, close a session, infer combat state, or reuse scenario-choice semantics.
- `AgeUpdateInteraction` presents the source-backed band/range and nonzero fifteen-column age changes and emits only the empty `age_update` acknowledgement payload.
- `PlayerMapInteraction` owns the negative-opcode immediate display stage. It renders the detached player-map payload through the same presenter used by Maps/Notes and emits only the empty acknowledgement for the matching request ID; closing it cannot mutate acquisition state or bypass the issuing VM frame.
- `TreasureDistributionInteraction` owns `fumbled-item-recovery`, `ordinary`, and `completion-confirmation`. Fumble mode emits only exact-instance assign/leave payloads. Ordinary mode renders pending item/knowledge, pooled wealth, legal recipients and reasons, Pool/Share, exact denomination transfers, Detect/Identify caster choices, and Done. Completion mode explicitly confirms or cancels abandonment.
- `LevelUpInteraction` owns `result` and `spell-selection`. It acknowledges the exact character result or returns one validated set of stable spell IDs; it never rolls, applies gains, computes eligibility, or changes character state.
- `TempleInteraction` renders one detached selected character, the first five supplied conditions, all supplied source-priced services, and Pool/Share/Leave controls. It may disable a service only from supplied pooled-plus-personal affordability and emits only stable character/service identity or the named wealth action.
- `BankInteraction` renders only supplied pooled, banked, personal, load, Pool/Share, exact-increment, selection, and unavailable-reason facts for `BANK` and `POOLED_WEALTH_DEPARTURE`. It emits Pool, Share, one stable character/denomination transfer, or Done. It never performs bank import/return, clears a pool, resumes movement, recomputes capacity, or turns Done into a deposit.
- `BattleInteraction` consumes the request's weapon mode, rules-owned melee/projectile targets, legal-action list, typed Escape availability, core-proven spell/power/target/cost combinations, and source-probed charged-item/power/target combinations. Cast and item responses carry only actor, action, and stable item/spell/target identities plus spell power or selected battlefield coordinate/rotation where supplied. Automatic groups use an empty target ID plus the core-provided group label and omit individual HP. Actor, repeated-actor, and spatial workflows configure the presentation-owned battlefield target state; spatial spells use the request's exact Data AD offsets and rules-owned legal centers. The component never recalculates spell or item legality, masks, occupants, range, LOS, charges, or effects. Disabled Escape, Fire, spell, and item actions use typed reasons and cannot synthesize targets or tactical facts. Guard emits Castle's persistent defend command, while Finish is a separate response that clears Guard and remaining movement.
- `BattleInteraction` also consumes typed Auto Turn, Delay, Bandage, and Turn Undead probes. It emits the ordinary combat action plus at most one core-listed Bandage recipient; persistent character Auto is routed separately by the party roster and never masquerades as an activation command.
- The battle component is a full-window-width bottom command deck, not a full-stage modal. Its compact overview owns inspection and turn commands; one target/spell/item workflow may replace that overview at a time and must provide a visible Back to battle action within the 960x600 command region. Spatial movement remains with `ClassicBattlefieldPresenter` and stays suppressed until the secondary workflow is closed or committed.

# Local Contracts

- Never add gameplay facts, targets, prices, eligibility, or service availability that are absent from the request.
- Disabled controls require a specific player-facing reason.
- Every pointer action must also be keyboard focusable.

# Work Guidance

- Keep request-kind logic in the narrowest component and preserve payload field names exactly.
- Repeated combat spells render core-supplied candidates, retain explicit addition order, permit one through `maximumTargets`, and emit that order as `targetIds`. Presentation cannot infer extra targets or reorder the selection.
- Battlefield target cancellation emits no response. Confirmation preserves the existing combat payload ABI: one stable `targetId`, ordered `targetIds`, or one legal `targetCoordinate` plus rotation, according to the configured mode.

# Verification

- Run `tools/verify.ps1`; interaction fixtures verify request-ID and payload preservation.

# Child DOX Index
- No child AGENTS.md files are currently required.
