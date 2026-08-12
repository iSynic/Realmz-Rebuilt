# Architecture documentation contract

## Purpose

Own current architecture, ADRs, package/save contracts, fidelity decisions, oracle policy, development workflows, and delivery status.

## Ownership

- Durable design decisions and their consequences.
- Current roadmap and evidence-backed completion status.
- Castle/Providence/reference provenance without copied archaeology artifacts.
- Source/runtime evidence boundaries for topology and each source-backed gameplay domain.

## Local Contracts

- Describe current target behavior, not a diary of implementation attempts.
- Separate proven Castle behavior, target Realmz 2.0 behavior, and inference.
- Every fidelity correction records source/control-flow evidence, observable oracle behavior, player-facing problem, chosen result, and tests.
- Application-hook evidence records the Providence compiler pin `2ce5a512d9754d3b3d000641edbfc96884e7e14e` and keeps direct `GameSession` proof separate from scenario-VM-owned caller coverage; a hook case or workflow remains partial while any caller path is unresolved.
- Classic media documentation distinguishes shared resource identity from Castle's effective compositing steps; the battle viewport contract records both the active landlook and shared PICT 302 inputs.
- Roadmap phases remain tied to their approved exit gates.
- `docs/development.md` is the operational source of truth for risk tiers, workflow batches, Luna delegation, and delivery evidence; `roadmap.md` records the current and future batch interpretation without rewriting historical evidence.
- The risk-tiered delivery policy is an operating contract, not an ADR. Add an ADR only when a separate non-local architectural boundary changes.

## Work Guidance

- Keep prose practical and concrete about data flow, ownership, invariants, and verification.
- Add an ADR when changing a non-local architectural boundary.
- Keep generated workflow status and source-intelligence artifacts derived from their inventory/generator; do not hand-edit them as part of a documentation pass.

## Verification

- The DOX closeout pass checks every affected index and removes stale contracts.

## Child DOX Index

- `adr/` contains immutable decision records and follows this contract; no additional child AGENTS.md is currently needed.
- `gameplay-domain-evidence.md` owns Phase 4 Castle source ranges, bounded campaign-inventory provenance, and the distinction between source, runtime-unit, integration, and live-route proof.
- `classic-functional-differential.md` owns the current human-readable Remake-versus-2.0 comparison status and links each rolling slice to its machine-readable evidence case.
- `classic-application-workflow-status.md` is generated from the authoritative workflow inventory and owns the current Classic and host completeness totals, domain heatmap, blockers, oracle unknowns, and prioritized queues. Never edit it independently of the inventory and generator.
- `scenario-vm-evidence.md` owns Classic control-flow, nested macro, and host-boundary evidence.
- `codemap/AGENTS.md` owns the generated source-intelligence encyclopedia, embedded source snapshot, machine graph, retrieval chunks, and evidence boundaries.
- `ui-strategy.md` owns the canonical visual language, responsive profiles, route/screen matrix, scaling, input, accessibility, media, and fidelity boundaries.
