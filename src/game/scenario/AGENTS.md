# Scenario game model

## Purpose

Own immutable compiled scenario definitions and the mutable scenario-progress state carried by one playthrough.

## Ownership

- Authored scenario programs, instructions, encounters, rewards, services, and safe-action definitions.
- `ScenarioProgressState` for searched cells, quests, journal discovery, and the current selected-character set.
- `ScenarioEncounterState` for timed encounter records, eliminated results, attempt counts, thief flags, and program redirects.

## Local Contracts

- Compiled definitions remain immutable after package construction.
- Progress state preserves the established flat save fields; its in-memory feature boundaries do not create a save migration.
- Character selection resolves through the owning `PartyState` and may not retain duplicate or unknown identities.
- Scenario execution and VM frames remain under `src/scenarios`; this folder contains only pure game definitions and state.

## Work Guidance

- Add authored content to the nearest `content`, `instructions`, or `safe` family.
- Add mutable scenario truth to the smallest named state owner rather than growing `GameState`.

## Verification

- `tests/scenario/test_scenario_vm.gd` protects scenario progress, control flow, and save round trips.
- `tests/integration/test_session_persistence.gd` protects the complete persisted aggregate.

## Child DOX Index

