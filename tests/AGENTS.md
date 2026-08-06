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
- `tests/fixtures/packages/fixture-provenance.json` owns the hashes and Providence commit for both the positive `.realmz2` fixture and its valid-ZIP stale-hash negative derivative. The current fixture contains two land maps, one packed-source dungeon map, explicit topology features, and Layout transitions.

## Work Guidance

- Keep failures deterministic and include stable IDs and draw indices in diagnostics.
- Add save/reload coverage at every interaction boundary.

## Verification

- `godot --headless --path . --script res://tests/test_runner.gd` runs the typed GDScript suite.
- `tools/verify.ps1` runs import/script checks, tests, architecture guards, and `git diff --check`.

## Child DOX Index

- No child AGENTS.md files are currently required; fixture subtrees inherit this contract.
