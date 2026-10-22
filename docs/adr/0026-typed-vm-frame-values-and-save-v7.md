# ADR 0026: Typed VM frame values in save v7

Status: accepted for the VM schema 4 / save v7 batch.

## Problem

`ScenarioFrame.to_data()` writes Safe Scenario Action `parameters`, `locals` and `iterators`, and `ScenarioVmSnapshot` writes `lastOutcome`, as raw Variants. Saves are JSON, and Godot's JSON reader returns every number as a float. After a save and load, a suspended Safe Action can resume with `3.0` where it held `3`:

- `SafeExpressionEvaluator.value_matches_type(&"int")` requires `is int`, so typed returns and call arguments fail after restore.
- Division switches from integer to float semantics, so the same program gives a different result than it would have without the save. That breaks the deterministic-restore contract.

`ScenarioActionState` already avoids this by tagging every value (`{"type": "int", "value": 3}`); the frame codec is the inconsistent one. Classic program frames do not use parameters or locals, and Codex's audit found no Safe Scenario Actions in the 13 bundled campaigns, the application library or the 65 examined corpus contexts. Current players are not exposed, but the contract is wrong for any authored Safe Action that yields mid-run.

## Decision

1. Extract the tagged encoder and decoder from `ScenarioActionState` into one shared `ScenarioValueCodec` (null, bool, int, float, string, array, record; depth limit 32; finite floats only). `ScenarioActionState` keeps its existing wire bytes; this is a move, not a format change.
2. VM snapshot schema 4 encodes frame `parameters`, `locals`, iterator values and `lastOutcome` through that codec. Strict decoding rejects untagged values in schema 4.
3. Save format v7 carries VM schema 4. Rebuilt writes v7 and reads v5, v6 and v7. Older builds reject v7 with their existing version message.
4. Schema 2/3 frames (from v5/v6 saves) keep their raw decoded values with two exceptions. When the VM restores the frame, a whole float becomes `int` only where the Safe Action declares that parameter as `int`; locals carry no declarations and keep their decoded types. The VM-owned loop counters `index` and `beginTarget` are always integers. There is no recursive whole-float-to-int conversion, because legitimate floats and integer division would become ambiguous. A value that still mismatches its declared type fails explicitly when it is used, as today. An unrestored legacy snapshot nested inside a continuation keeps its schema-3 shape until its VM restores it, so the coercion is never skipped.
5. Loading never rewrites a file. A v6 save becomes v7 only when the player saves again.

## Consequences

- Safe Action values keep their exact types across save/load, so restored and uninterrupted runs match.
- One codec owns tagged values for both action state and frames, so they cannot drift again.
- v7 saves cannot be opened by earlier builds, as with every save bump. Character Files v2 and package schema v7 do not change.
- Update Save copies and pinned save-update policies keep their exact eligibility rules; they write through the current writer, so new copies are v7. A copied envelope whose VM was never restored keeps its schema-3 VM inside v7, and restore still applies the coercion. This ADR does not broaden any update policy.

## Verification

- A public VM workflow suspends a Safe Action holding int, float, array and record locals, round-trips the snapshot through the real save JSON path, resumes, and asserts identical types, `value_matches_type` results and integer-division output against an unsaved run.
- Wire tests prove schema 4 rejects untagged values, schema 2/3 decode with declared-type coercion only, and `ScenarioActionState` bytes are unchanged.
- Save repository tests write v7 and read v5/v6/v7.

## Relationship to ADR 0027

ADR 0027 also changes VM snapshot fields. Both land in the same VM schema 4 / save v7 so players see one version boundary.
