# Playthrough character workflow contract

## Purpose

Own character creation, party admission, finalization, and lifecycle transactions above pure character state and rules.

## Ownership

- `CharacterCreationSession` owns the standalone typed creation transaction.
- `LifecyclePartyWorkflow` owns reusable-character admission, party insertion, Begin Adventure, age checks, and lifecycle party operations.
- `CharacterFinalizeWorkflowResult` carries typed finalization outcomes back to the session boundary.
- `AgeContinuationBody` retains the source-ordered age acknowledgement needed to resume a saveable transaction.
- `CharacterContinuations` constructs starting-spell, Character Files publication, and age-update continuations from their feature-owned payloads.
- `CharacterSpellConfirmationContinuationBody` and `CharacterVaultPublicationContinuationBody` carry only their distinct character-setup facts.
- `PartyIntents` and `PartyIntentPayloads` define the typed commands accepted for party assembly, Character Files, creation, and appearance work.
- `CharacterCreationSpec` is the typed creation command value; workflows mutate the saveable `CharacterDraftState` owned by `src/game/characters`. Age and level decisions consume that feature's detached request bodies.

## Local Contracts

- Character truth and calculations remain in `src/game/characters`; these workflows coordinate them through `SessionWorkflowContext`.
- Character Files import validates active-campaign race, caste, item, load, spell, scroll, Fast Spell, portrait, and combat-icon identities before one insertion.
- Standalone Character Files publication rebases workshop party-owned item IDs and equipped order to the stable Character File identity before storage.
- Every failed admission leaves the party and reusable Character Files revision unchanged.
- Creation and aging preserve Castle RNG order, stable identities, continuation fields, and save representation.
- Character continuation kinds remain distinct typed payloads even though their saved field names are unchanged.
- `GameSession` alone commits, rolls back, changes revision, and constructs the public step.

## Work Guidance

- Begin with `CharacterCreationSession` for a new adventurer and `LifecyclePartyWorkflow` for an existing Character Files revision or party lifecycle event.
- Add calculations to `CharacterRules`, not to the orchestration layer.

## Verification

- `tests/core/test_character_creation_session.gd` owns standalone creation transactions.
- `tests/core/test_realmz_rules.gd` owns pure character calculations and RNG order.
- Character Files, party-order, appearance, and session-persistence suites own reusable and saveable behavior.

## Child DOX Index
