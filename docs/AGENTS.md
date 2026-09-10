# Architecture documentation contract

## Purpose

Own current architecture, ADRs, package/save contracts, fidelity decisions, oracle policy, development workflows, and delivery status.

## Ownership

- Durable design decisions and their consequences.
- Current roadmap and evidence-backed completion status.
- The human-maintainability migration charter, source vocabulary, naming rules, and scene-ownership target.
- Public Beta 1 installation, licensing, known-limitations, feedback, and release-acceptance documentation.
- Castle/Providence/reference provenance without copied archaeology artifacts.
- Source/runtime evidence boundaries for topology and each source-backed gameplay domain.

## Local Contracts

- Describe current target behavior, not a diary of implementation attempts.
- Separate proven Castle behavior, target Realmz 2.0 behavior, and inference.
- Every fidelity correction records source/control-flow evidence, observable oracle behavior, player-facing problem, chosen result, and tests.
- Application-hook and media evidence records the Providence compiler pin from `docs/references.lock.json` and keeps direct `GameSession` proof separate from scenario-VM-owned caller coverage; a hook case or workflow remains partial while any caller path is unresolved.
- Classic media documentation distinguishes application-owned resource families, scenario-owned exact overrides, and Castle's effective compositing steps; the battle viewport contract records both the active landlook and shared PICT 302 inputs.
- Roadmap phases remain tied to their approved exit gates.
- `docs/development.md` is the public operational source of truth for risk tiers, workflow batches, contributor checks, and delivery evidence; internal delegation rules remain in the root contract. `roadmap.md` contains only current evidence, remaining work, and release order. Historical commit-by-commit narration belongs in private Git recovery history, not the public roadmap.
- Parity-convergence status is generated from the workflow inventory's current batch, baseline counts, certification targets, and owned gaps. AP testing follows the failure-first order in `development.md`; the 13 pinned bundled scenarios are the representative breadth target, while inventory denominators remain authoritative and static opcode presence is not runtime coverage. Full campaign certification is separate from, and does not gate, cross-scenario AP testing.
- The risk-tiered delivery policy is an operating contract, not an ADR. Add an ADR only when a separate non-local architectural boundary changes.

## Work Guidance

- Keep prose practical and concrete about data flow, ownership, invariants, and verification.
- Add an ADR when changing a non-local architectural boundary.
- Keep generated workflow-status artifacts derived from their authoritative inventory; do not hand-edit them as part of a documentation pass.

## Verification

- The DOX closeout pass checks every affected index and removes stale contracts.

## Child DOX Index

- `adr/` contains immutable decision records and follows this contract; no additional child AGENTS.md is currently needed.
- `gameplay-domain-evidence.md` owns Phase 4 Castle source ranges, bounded campaign-inventory provenance, and the distinction between source, runtime-unit, integration, and live-route proof.
- `classic-functional-differential.md` owns the current human-readable Remake-versus-2.0 comparison status and links each rolling slice to its machine-readable evidence case.
- `fidelity-ledger.md` owns named corrections such as the bounded Delay and Bandage decisions; each entry links a source-observation fixture and chosen-result tests without upgrading source flow into a runtime claim.
- `classic-application-workflow-status.md` is generated from the authoritative workflow inventory and owns the current batch, count deltas, Classic and host completeness totals, domain heatmap, blockers, oracle unknowns, and prioritized queues. Never edit it independently of the inventory and generator.
- `classic-gameplay-parity-status.md` is generated from the complete opcode registry and pinned application spell catalog. It summarizes the committed parity denominator and evidence boundaries; never edit it independently of `tools/gameplay_parity_inventory.gd`.
- `scenario-vm-evidence.md` owns Classic control-flow, nested macro, and host-boundary evidence.
- `ui-strategy.md` owns the canonical visual language, responsive profiles, route/screen matrix, scaling, input, accessibility, media, and fidelity boundaries.
- `ui-visual-audit.md` owns the complete player-visible screen/state inventory, Castle/Remake design leads, target composition decisions, media opportunities, and phased visual-remediation queue.
- `runtime-performance.md` owns the current startup, package-prewarm, vault-insertion, and rendered-overworld performance evidence, acceptance boundaries, and machine-specific measured results.
- `runtime-testing.md` owns the developer-only game-aware testing protocol, isolated-fixture/live-access boundary, proof modes, and normalized Castle comparison contract.
- `builders-manual.md` is the public, newcomer-facing map of repository ownership, command flow, Godot scene practice, and maintainer workflow.
- `maintainer-acceptance.md` owns the public, hint-free newcomer exercise and its evidence ledger for the six required architecture journeys.
- `architecture-migration.md` records the completed current architecture, its enforced limits, verified baseline, and remaining acceptance without preserving a chronological implementation diary.
- `human-centered-architecture.md` owns the active Beta-blocking migration charter, verified structural baseline, performance baseline, and working rules.
- `system-manifest.json` is the machine-checked index of final feature directories, systems, entry points, public interfaces, owning tests, performance probes, and major UI surfaces.
- `features/` contains concise public guides for navigating each current game system while its physical feature roots are migrated.
- `beta-1.md` owns public prerelease scope, candidate-walkthrough requirements, blocking severity, known limitations, and bug-report evidence expectations.
