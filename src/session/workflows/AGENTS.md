# Session workflow contract

## Purpose

Own domain-oriented, presentation-independent operations invoked by the session transaction coordinator.

## Ownership

- Lifecycle and party setup.
- Exploration and time.
- Inventory, magic, and services.
- Combat and rewards.
- Scenario application-hook protocol preparation.
- Detached `GameView` projection.

## Local Contracts

- Operations receive an ephemeral `SessionWorkflowContext` and never retain the session or context.
- Domain mutations use core rules and state; callers own transaction rollback, request IDs, revisions, pending interactions, and exact-once commit.
- A workflow returns typed results or existing core result types. It does not construct `SessionStep` values or call another public session operation.
- Direct intents and scenario handlers must converge on the same core rule operation when they represent the same Realmz action.
- View projection is read-only and must not create gameplay truth or mutate state.

## Verification

- Focused public session and VM workflows cover each extracted owner; implementation-private coordinator tests are not admission evidence.

## Parent Contract

- See `../AGENTS.md`.

## Child DOX Index

- No child contracts are required.
