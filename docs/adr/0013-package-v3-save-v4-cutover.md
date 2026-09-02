# ADR 0013: Cut over to package v3 and save v4

## Status

Accepted; implementation in progress.

## Context

The unpublished package and save contracts accumulated defaults, aliases, migrations, and repeated startup validation. Retaining those paths would preserve complexity that has no released compatibility obligation.

## Decision

Providence emits only strict `.realmz2` schema v3 with normalized mandatory runtime data. Rebuilt validates external bytes once during installation, writes a receipt keyed by package hash, schema hash, and decoder version, and uses that receipt for later startup. Package v1/v2 is rejected.

`.r2save` v4 stores the typed `SessionSnapshot` and closed protocol variants. Save v1 through v3 is rejected without migration. Existing packages must be re-exported and existing saves are reported as incompatible.

## Consequences

The clean cut removes compatibility branches and makes startup trust explicit. It does not authorize changes to Classic behavior, RNG order, topology semantics, or player-visible workflow outcomes.
