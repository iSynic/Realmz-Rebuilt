# Scenario game model

## Purpose

Own immutable compiled scenario definitions and the mutable scenario-progress state carried by one playthrough.

## Ownership

- Authored scenario programs, instructions, encounters, rewards, services, and safe-action definitions.
- `content/` owns the immutable campaign aggregate, restrictions, narration, labels, triggers, and direct encounter records.
- `RealmzContent` composes the named character, item, magic, combat, economy, world, and scenario catalogs without forwarding their lookup APIs.
- `ScenarioContentCatalog` indexes campaign narration, option labels, triggers, and direct encounter definitions.
- `ScenarioProgressState` for searched cells, quests, journal discovery, and the current selected-character set.
- `ScenarioEncounterState` for timed encounter records, eliminated results, attempt counts, thief flags, and program redirects.
- `CampaignSummaryView` carries the detached campaign facts shown during selection without making discovery load the complete package.
- Complex Encounter, Thief Encounter, and Pick Lock request bodies carry detached scenario decisions without exposing VM frames.

## Local Contracts

- Compiled definitions remain immutable after package construction.
- Progress state preserves the established flat save fields; its in-memory feature boundaries do not create a save migration.
- Character selection resolves through the owning `PartyState` and may not retain duplicate or unknown identities.
- Scenario execution and VM frames remain under `src/scenarios`; this folder contains only pure game definitions and state.
- `RealmzContent.scenario_records` is the direct immutable lookup surface; `RealmzContent.scenario` remains the compiled program graph.
- Scenario request bodies are pure cross-boundary values; VM mutation remains under `src/scenarios` and transaction ownership remains under `src/playthrough`.

## Work Guidance

- Add authored content to the nearest `content`, `instructions`, or `safe` family.
- Add mutable scenario truth to the smallest named state owner rather than growing `GameState`.

## Verification

- `tests/scenario/test_scenario_vm.gd` protects scenario progress, control flow, and save round trips.
- `tests/integration/test_session_persistence.gd` protects the complete persisted aggregate.

## Child DOX Index
