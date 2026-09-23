# Shared interaction contract

## Purpose

Own the pure request/response envelopes, neutral request bodies, and strict decoder registry shared by game rules, scenario execution, playthrough orchestration, persistence, and presentation.

## Ownership

- `InteractionRequest`, `InteractionResponse`, and `InteractionRequestBody` define the stable cross-boundary protocol.
- Neutral acknowledgement, choice, character-selection, general-selection, lifecycle, and yes/no bodies with their exact `to_data()` representation.
- Request-specific equality helpers used by restore validation.
- Dialog, selection, thief, service/combat, and reward top-level request decoders.
- Shared, service, combat, reward, and selection nested-value decoders plus their common wire-shape predicates.

Feature-specific request bodies live under their character, economy, combat, or scenario game feature.

## Local Contracts

- Bodies extend `InteractionRequestBody` and remain pure values.
- Existing serialized kinds, fields, versions, and optional-field presence remain stable. Shop responses additionally admit optional `denomination` and `amount` for source-backed Shop Swap and changing, plus `targetCharacterId` for exact-instance Trade; strict decoding still rejects unknown or mistyped fields.
- Request decoding remains strict and rejects unknown or mixed fields.
- Optional item icon keys are paired exact resource type and signed nonzero ID values. Inventory, Shop stock, and Treasure records preserve both fields through decoding and serialization; zero denotes an absent key, never a positive-only admission rule.
- Bodies never retain session state, Nodes, repositories, media bytes, or live continuations.
- New callers use the top-level body class directly; do not add nested compatibility aliases to `InteractionRequest`.
- Callers address the feature decoder that owns a nested record. Do not reintroduce a central forwarding value decoder.

## Work Guidance

- Add a feature request body beside its owning game model and register its stable kind in the central decoder.
- Keep the central request class limited to kind registration, construction, and codec dispatch; each feature decoder admits only its registered stable kinds.

## Verification

- Run the owning gameplay, restore, scenario, and presentation suites for a moved family.
- Run the complete gate at the owning batch boundary.

## Child DOX Index
