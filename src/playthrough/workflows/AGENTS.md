# Remaining playthrough workflow contract

## Purpose

Own feature workflows that have not yet moved from this migration directory into their final human-facing feature roots.

## Ownership

- Scenario application hooks.

## Local Contracts

- Every workflow receives an ephemeral `SessionWorkflowContext` and never retains the session or context.
- Domain mutation uses `src/game` rules and state; `GameSession` owns rollback, request IDs, revisions, pending interactions, and exact-once commit.
- Direct intents and scenario handlers converge on the same operation when they represent the same Realmz action.
- Workflows return typed feature or session results and never construct `SessionStep` values.
- Preserve stable continuation payloads, RNG order, event order, and save representation while moving ownership.

## Work Guidance

- Move each workflow with its continuations, documentation, manifest ownership, and tests into the corresponding feature root.
- Do not add new generic workflows here; new behavior belongs directly to a named feature.

## Verification

- Run the owning core or integration suite for each moved workflow.
- Run `tools/verify.ps1` before completing a workflow batch.

## Child DOX Index
