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
- Roadmap phases remain tied to their approved exit gates.

## Work Guidance

- Keep prose practical and concrete about data flow, ownership, invariants, and verification.
- Add an ADR when changing a non-local architectural boundary.

## Verification

- The DOX closeout pass checks every affected index and removes stale contracts.

## Child DOX Index

- `adr/` contains immutable decision records and follows this contract; no additional child AGENTS.md is currently needed.
- `gameplay-domain-evidence.md` owns Phase 4 Castle source ranges, bounded campaign-inventory provenance, and the distinction between source, runtime-unit, integration, and live-route proof.
- `classic-functional-differential.md` owns the current human-readable Remake-versus-2.0 comparison status and links each rolling slice to its machine-readable evidence case.
- `scenario-vm-evidence.md` owns Classic control-flow, nested macro, and host-boundary evidence.
- `codemap/AGENTS.md` owns the generated source-intelligence encyclopedia, embedded source snapshot, machine graph, retrieval chunks, and evidence boundaries.
- `ui-strategy.md` owns the canonical visual language, responsive profiles, route/screen matrix, scaling, input, accessibility, media, and fidelity boundaries.
