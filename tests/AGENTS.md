# Test and oracle evidence contract

## Purpose

Own deterministic automated proofs, synthetic fixtures, oracle provenance, route evidence, and the boundary between observed Classic behavior and chosen Rebuilt behavior.

## Ownership

- Unit, wire-contract, public-session workflow, presentation-invariant, and ordinary-route test lanes.
- Synthetic Providence-authored package fixtures and controlled Castle oracle fixtures.
- Fixture manifests containing source commit, source symbol/range, inputs, scripted RNG, hashes, and observations.
- Developer-only fixture gallery and local capture harnesses.

## Local Contracts

- Label evidence as `source-control-flow`, `castle-runtime`, `runtime-unit`, `runtime-integration`, or `live-route`. Source reading is not runtime proof, and parser round trips are not independent layout proof.
- Castle fixtures use pinned commit `491816ad60037394f92c428e99c004494d3c28b3` and synthetic data. Never commit extracted commercial campaign payloads, user saves, generated Castle installations, or local screenshots.
- Provenance-checked application media from the openly licensed Castle repository may enter fixtures only under the presentation-asset contract with exact source commit, ownership, license, modifications, and byte hashes.
- Stock music tests consume only the committed provenance manifest and generated Ogg bank. They may prove integrity, context precedence, preference migration, and presentation behavior, but they do not upgrade later Castle restoration code into a pinned-runtime oracle or treat local gallery playback as ordinary campaign evidence.
- `tests/fixtures/packages/fixture-provenance.json` owns package hashes, Providence provenance, and the tracked synthetic package description. Detailed source conclusions belong in the differential ledger, fidelity decisions, or domain evidence documents—not in this operational contract.
- Use injected `ScriptedRng` and scripted input when two implementations must exercise the same branch. Diagnostics include stable IDs and draw indices.
- Preserve complete save/reload evidence at mandatory interaction boundaries and exact-once terminal combat/reward boundaries.
- The public exploration workflow owns boat fidelity proof: boarding, water traversal, repeated shore collision, accepted/declined choices, exact sounds/time, authoritative tile-60/tile-147 overlays, and save/resume. Do not duplicate those assertions in topology, package, presentation, and route suites; those layers retain only their distinct contract responsibilities.
- The public exploration workflow also owns Search-mode versus Area-Search timing, field Heal time/SP/RNG/recovery and save restoration, plus contextual Encounter availability, land-facing coordinate, draw/order, XAP 0 fallback, and continuation. The public inventory workflow owns exact item-805 Torch use. Presentation tests retain only command grouping, workspace structure, roster-mediated Trade, and responsive reachability.
- Public exploration and combat workflows own source-backed simulation action-cue event IDs and ordering. Presentation tests own physical held-cycle start cues plus repeat suppression, explicit workspace-entry cues, same-route suppression, and automatic-route suppression; they do not duplicate simulation sound requests.
- A test owns exactly one justified responsibility: architecture/wire invariant, non-obvious source-backed rule, complete public session workflow, general presentation lifecycle/layout invariant, or ordinary campaign route.
- Map a defect to an existing owning invariant before admitting a new test. Prefer table-driven cases and general lifecycle/layout proofs over one test per symptom.
- Do not test private methods of `GameSession`, `RealmzRuntimeApi`, `PackageRepository`, or `ClassicScreenRouter`. Do not duplicate one behavior across layers unless each layer protects a distinct failure responsibility.
- During rationalization, remove private presentation-helper assertions when an existing public lifecycle/layout invariant already owns the outcome. Do not replace a deleted incidental assertion with a larger helper-level test merely to preserve assertion counts.
- UI wording, helper copy, and isolated spacing normally receive gallery/manual acceptance rather than bespoke regression tests.
- Differential cases link to one owning automated proof. Assertion counts, suite counts, and differential-case counts are diagnostics, never completion metrics.
- The test-budget ratchet begins at 11,807 substantive lines, may only decrease during hotspot maintenance, and closes at no more than 7,900 lines, 20 percent of production, and 1,200 lines per suite. These caps eliminate duplicate/incidental proof; they never authorize removal of a unique high-risk or source-backed owner.
- RNG, VM, save, authoritative topology, package integrity, and exact-once terminal-combat coverage are high-value and may not be removed merely to reduce line count.
- A passing delegated-agent result is review input only; Sol validates integration and any audit-status change. Unknown or ambiguous Castle behavior remains explicit.

## Work Guidance

- Split large suites by public workflow ownership, not by individual bugs or implementation helpers.
- Every suite supports named focused cases through the shared test-case contract.
- Use fixture builders for repeated setup, but keep expected player-visible outcomes explicit at the owning public boundary.
- Keep presentation tests centered on primary-workspace exclusivity, modal input ownership, responsive reachability, detached information safety, and required Classic stage/roster/command structure.
- Keep local AOGM, War, and commercial-campaign routes outside version control; record only permitted evidence labels and durable conclusions.

## Verification

- `godot --headless --path . --script res://tests/test_runner.gd` runs the complete typed suite.
- `tools/run_tests.ps1 -Suite <fragment> -Case <fragment>` runs Tier 1 focused cases in one bounded Godot process and rejects unmatched filters, teardown leaks, and retained-resource warnings.
- `tools/verify_workflow.ps1` is the Tier 2 workflow gate. `tools/verify.ps1` is the Tier 3/CI authority.
- Package tests verify strict schema-v3 decoding, deterministic package identity, receipt trust, bounded cache lifetime, and explicit rejection of obsolete schemas.
- Save tests verify strict save-v4 variants, transactional restore, backup recovery, package mismatch, and explicit rejection of save v1-v3.
- Presentation acceptance checks the canonical 1280x720 composition and optional 800x600 Classic composition. Text/interface-scale checks run against those two compositions; intermediate or larger sizes may receive smoke coverage but are not independent visual-acceptance targets. Pending interactions block both route and map input.

## Child DOX Index

- `presentation/AGENTS.md` owns UI fixture/gallery coverage, responsive profile assertions, and local screenshot evidence boundaries.
- Fixture subtrees otherwise inherit this contract.
