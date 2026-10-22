# ADR 0028: Adventure rules and resumable combat rounds in save v8

Status: accepted.

An adventure may opt into free cancellation of uncommitted targeting. Classic cancellation remains the default. The rule is authoritative session state, separate from presentation settings and immutable campaign rules. A suspended round effect also needs durable progress: a death macro may revive a monster between disease and poison, so restarting the whole round would change both state and RNG.

- Store a typed, strictly decoded `AdventureRules` value in GameState and its detached snapshots. V8 requires `freeTargetingCancellation` as a boolean; unknown fields and malformed values reject.
- Retain random item powers by exact instance until that item is consumed or the activation ends. Cancel and Undo preserve those rolls; switching sources and save/restore never reroll or rewind shared RNG. V8 requires the combat cache array, including an empty one.
- Retain the round's next phase, actor index and pending death subject before yielding to an authored macro. The saved cursor requires the corresponding session or nested-VM continuation. Complete the remaining effects before ordinary automation or battle resolution.
- Write save v8 and read v5-v8. Earlier saves initialize Classic rules and preserve existing prepaid actions. A legacy suspended battle macro without a cursor does not replay effects already committed by that build.
- VM schema 4 was introduced in save v7. V5/v6 retain their legacy VM restriction; v7/v8 may carry schema 4 or an unrestored legacy VM copied through an explicit save update.
- Loading never writes. Earlier builds reject v8. Character Files v2, campaign packages and exact Update Save eligibility remain unchanged; explicit new writes use the existing verified transaction.

The optional rule's editing and reservation behavior are owned by the combat workflow. Combat text preferences remain presentation-only and never enter this record. Source-backed round ordering comes from Castle `getup.c` and `reduce.c`; this save representation is Rebuilt's continuation mechanism, not a claim of native save compatibility.
