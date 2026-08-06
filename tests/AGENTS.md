# Test and oracle evidence contract

## Purpose

Own deterministic tests, synthetic fixtures, oracle provenance, route evidence, and clear labels for what each observation proves.

## Ownership

- Unit, contract, integration, oracle, MCP/runtime, and certified-route test lanes.
- Synthetic Providence-authored fixtures and golden traces.
- Fixture manifests with source commit, function/range, inputs, RNG, hashes, and observations.

## Local Contracts

- Label evidence as `source-control-flow`, `castle-runtime`, `runtime-unit`, `runtime-integration`, or `live-route`.
- Never treat source reading as runtime proof or a parser round trip as independent layout proof.
- Castle fixtures use pinned commit `491816ad60037394f92c428e99c004494d3c28b3` and synthetic data.
- Do not commit extracted commercial campaign payloads, user saves, generated Castle installations, or copyrighted media.
- Tests requiring identical branches use injected scripted RNG/input.
- `tests/fixtures/packages/fixture-provenance.json` owns the hashes and Providence commit for both the positive `.realmz2` fixture and its valid-ZIP stale-hash negative derivative. The current fixture contains two land maps, one packed-source dungeon map, explicit topology features and Layout transitions, three random rectangles covering ordinary checks, a surprise battle, a one-shot XAP, an AP-to-AP post-action relocation pair, direct Complex/Thief/Timed Encounters, 799 bundled Classic items plus scenario supply/custom items, 420 normalized standard spells plus one packed scenario spell, two content-addressed media assets, and an AP to Simple Encounter to result to Scenario Action to XAP/CODE 111 route.
- `tests/fixtures/oracle/aogm-active-opcode-inventory.json` is a bounded content inventory only. Its source hash, counts, and normalized opcode set may prove compiler/runtime readiness coverage; it does not contain commercial records and makes no reachability or live-route claim.
- `tools/route_acceptance.gd` is a generic local harness. Certified route JSON, campaign packages, and emitted reports stay outside this repository when they contain or identify commercial campaign content.
- Direct ED3/XAP route checkpoints may name a compiled program explicitly; this proves that macro's ordinary VM behavior, not map reachability for an unplaced record.
- Post-battle tests preserve Castle's distinction between consumed held-over allies and the subsequent `bodycount()` survivor selection; route defaults must use the request's source-backed preselection rather than silently retaining all friendlies.
- Presentation tests compare 2D topology facts with the 3D geometry projection. Local MCP screenshots are visual evidence only and remain outside the repository.
- War in the Sword Lands certification uses an external route, package, and report. Only package/route hashes, stage names, and resulting observations may enter documentation.

## Work Guidance

- Keep failures deterministic and include stable IDs and draw indices in diagnostics.
- Add save/reload coverage at every interaction boundary.

## Verification

- `godot --headless --path . --script res://tests/test_runner.gd` runs the typed GDScript suite.
- `tools/verify.ps1` runs import/script checks, tests, architecture guards, and `git diff --check`.

## Child DOX Index

- No child AGENTS.md files are currently required; fixture subtrees inherit this contract.
