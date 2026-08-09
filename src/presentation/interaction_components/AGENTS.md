# Purpose

- Own typed, focusable presentation components for serializable `InteractionRequest` kinds.

# Ownership

- Components translate an existing request payload into controls and emit the exact response payload selected by the player.
- `InteractionPresenter` owns request identity, modal visibility, and construction of `InteractionResponse`.
- `AgeUpdateInteraction` presents the source-backed band/range and nonzero fifteen-column age changes and emits only the empty `age_update` acknowledgement payload.
- `TreasureDistributionInteraction` currently owns mode `fumbled-item-recovery`: it displays the exact item/charge count, legal recipients and disabled reasons, and emits only assign or leave-behind payloads for the request's instance ID.
- `BattleInteraction` consumes the request's weapon mode, adjacent targets, legal-action list, and eight precomputed movement options. Move responses carry only the actor, `move` action, and selected destination; disabled steps and Fire use typed reasons and cannot synthesize targets or tactical facts.

# Local Contracts

- Never add gameplay facts, targets, prices, eligibility, or service availability that are absent from the request.
- Disabled controls require a specific player-facing reason.
- Every pointer action must also be keyboard focusable.

# Work Guidance

- Keep request-kind logic in the narrowest component and preserve payload field names exactly.

# Verification

- Run `tools/verify.ps1`; interaction fixtures verify request-ID and payload preservation.

# Child DOX Index
- No child AGENTS.md files are currently required.
