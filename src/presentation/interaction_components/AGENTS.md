# Purpose

- Own typed, focusable presentation components for serializable `InteractionRequest` kinds.

# Ownership

- Components translate an existing request payload into controls and emit the exact response payload selected by the player.
- `TextChoiceInteraction` renders yes/no as one compact response row and authored indexed/scenario options as numbered semantic choices in the response pane. It may add `Take note` to a journal-eligible Classic acknowledgement and emits only `{ "takeNote": true }`; ordinary Continue remains an empty acknowledgement, and an already-recorded message exposes no duplicate mutation.
- `EncounterInteraction` preserves one stable original-art Action, Items, Skills, Speak, Spells, and Stop strip. Selecting a mode replaces only its contextual choice, word, item, or spell pane; unavailable commands remain disabled in place with an exact reason, and every submission retains the existing typed complex-encounter body.
- `InteractionPresenter` owns request identity, modal visibility, and construction of `InteractionResponse`.
- `SelectionInteraction` keeps the active character prompt in the Classic textbox while `ClassicPartyRoster` owns the numbered portrait interaction; it must not recreate a checklist or a separate Choose button. Ally body-count selection remains in its dedicated list.
- `LifecycleInteraction` renders only the host-supplied End Adventure operations and emits one declared action identity. It does not save, close a session, infer combat state, or reuse scenario-choice semantics.
- `AgeUpdateInteraction` presents the source-backed band/range and nonzero fifteen-column age changes and emits only the empty `age_update` acknowledgement payload.
- `PlayerMapInteraction` owns the negative-opcode immediate display stage. It renders the detached player-map payload through the same presenter used by Maps/Notes and emits only the empty acknowledgement for the matching request ID; closing it cannot mutate acquisition state or bypass the issuing VM frame.
- `ThiefEncounterInteraction` owns the dedicated character-and-eight-action workspace supplied by the typed request. `PickLockInteraction` renders its deterministic tumbler frames at the supplied cadence, holds the final source second, and emits only the selected frame index. Neither component rolls RNG, recomputes ability values, mutates encounter flags, or invents a cancel outcome absent from Castle's picker.
- `TreasureDistributionInteraction` owns `fumbled-item-recovery`, `ordinary`, and `completion-confirmation` in one three-pane application workspace: current exact item, legal recipients, and fixed wealth/lore/completion commands. Fumble mode emits only exact-instance assign/leave payloads. Ordinary mode renders the request's one pending item/knowledge record and remaining count, pooled wealth, legal recipients and reasons, Pool/Share, exact denomination transfers, Detect/Identify caster choices, and Done. It does not invent a complete item pile or item illustration when those identities are absent from the typed request. Completion mode explicitly confirms or cancels abandonment.
- `ShopInteraction` keeps its supplied party shoppers, stock, selected character inventory, and item inspector visible together. Shopper, stock, and carried-item selection are presentation-only; Buy, Sell, Identify, and Leave emit the existing exact typed payloads and preserve supplied availability reasons. Portraits, item art, load, capacity, and derived statistics remain absent until the request contract carries them.
- `LevelUpInteraction` owns `result` and `spell-selection`. It acknowledges the exact character result or returns one validated set of stable spell IDs; it never rolls, applies gains, computes eligibility, or changes character state.
- `TempleInteraction` renders one detached selected character, the first five supplied conditions, all supplied source-priced services, and Pool/Share/Leave controls. It may disable a service only from supplied pooled-plus-personal affordability and emits only stable character/service identity or the named wealth action.
- `BankInteraction` renders only supplied pooled, banked, personal, load, Pool/Share, exact-increment, selection, and unavailable-reason facts for `BANK` and `POOLED_WEALTH_DEPARTURE`. It emits Pool, Share, one stable character/denomination transfer, or Done. It never performs bank import/return, clears a pool, resumes movement, recomputes capacity, or turns Done into a deposit.
- `BattleInteraction` consumes the request's weapon mode, rules-owned melee/projectile targets, legal-action list, typed Escape availability, staged spell/power/cost choices, and source-probed charged-item/power/target combinations. Cast and item responses carry only actor, action, and stable item/spell/target identities plus spell power or selected battlefield coordinate/rotation where supplied. Automatic groups use an empty target ID plus the core-provided group label and omit individual HP. Memorized-spell targeting may select any request-provided living battlefield footprint or center, previews only the supplied Data AD offsets, and leaves final actor/range/LOS/mask legality to the core response transaction. Charged-item and scroll targeting retains its pre-probed candidates. The component never recalculates spell or item legality, masks, occupants, range, LOS, charges, or effects. Disabled Escape, Fire, spell, and item actions use typed reasons and cannot synthesize targets or tactical facts. Guard emits Castle's persistent defend command, while Finish is a separate response that clears Guard and remaining movement.
- `BattleInteraction` also consumes typed Auto Turn, Delay, Bandage, and Turn Undead probes. It emits the ordinary combat action plus at most one core-listed Bandage recipient; persistent character Auto is routed separately by the party roster and never masquerades as an activation command.
- The battle component is a full-window-width bottom command deck, not a full-stage modal. Its compact beveled overview keeps active and inspected facts beside a request-ordered initiative strip rotated to `NOW` and `NEXT`; presentation-supplied combat icons identify actors, with short names retained as the missing-icon fallback. Battle-specific theme margins keep both permanent command rows inside the canonical 1280x720 combat region; unavailable commands stay in place with their supplied reason instead of making neighboring controls reflow. One target/spell/item workflow may replace that overview at a time and must provide a visible Back to battle action in both the canonical composition and optional 800x600 Classic mode. When battlefield targeting begins, that workflow hides its setup selectors and shows only Back, status, Confirm, and Cancel; cancellation restores the selectors. Spatial movement remains with `ClassicBattlefieldPresenter` and stays suppressed until the secondary workflow is closed or committed.
- Memorized combat spell selection replaces the persistent party rail with one Classic-shaped spellbook: available spell-level rail, unique spell list, legal power choices, supplied cost/target facts, and explicit Aim/Cast plus Back actions. The bottom deck retains only workflow/targeting status and confirmation. The spellbook passes the exact selected `CastOption` back to `BattleInteraction`; it never reconstructs legality or submits directly to the session.

# Local Contracts

- Never add gameplay facts, targets, prices, eligibility, or service availability that are absent from the request.
- Disabled controls require a specific player-facing reason.
- Every pointer action must also be keyboard focusable.

# Work Guidance

- Keep request-kind logic in the narrowest component and preserve payload field names exactly.
- Repeated combat spells retain explicit addition order, permit one through `maximumTargets`, and emit that order as `targetIds`. Memorized spells use the request's living combatant roster for selection and defer final legality to submit; scrolls retain core-probed candidates. Presentation cannot reorder the selection or commit gameplay state.
- Battlefield target cancellation emits no response. Confirmation preserves the existing combat payload ABI: one stable `targetId`, ordered `targetIds`, or one legal `targetCoordinate` plus rotation, according to the configured mode.

# Verification

- Run `tools/verify.ps1`; interaction fixtures verify request-ID and payload preservation.

# Child DOX Index
- No child AGENTS.md files are currently required.
