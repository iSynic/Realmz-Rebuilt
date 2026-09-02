# ADR 0014: Realmz application content ownership

## Status

Accepted.

## Context

Classic Realmz opens application resources separately from scenario resources. Stock rules, spell text, controls, fonts, sounds, PICTs, and CICNs belong to Realmz itself. Copying those records into every compiled campaign makes a scenario appear to own data it never shipped, multiplies package size, permits campaign output to erase stock presentation, and obscures Castle's exact scenario-before-application override behavior.

## Decision

Realmz Rebuilt ships one pinned, versioned stock Realmz application library. Providence campaign output contains only original scenario-owned content plus normalized references to stock identities. Scenario definitions overlay the application catalog by exact stable identity; the scenario record wins for that active campaign, while every unmentioned definition remains application-owned. Scenario media follows the equivalent exact resource-type-and-ID precedence proved by Castle's resource chain.

Providence validates a campaign against the application-library contract but does not embed that library in the campaign. Rebuilt requires a matching `rulesVersion`, composes the two immutable typed inputs before cross-reference validation, and constructs the session from the effective catalog. Missing stock content is a Rebuilt build/install defect; missing scenario content is a campaign readiness defect.

Portable character inventory stores `ItemInstance` records: a stable `definitionId` plus per-copy mutable state such as charges, identification, and equipped status. It never copies an `ItemDefinition`. Import, load, carried-weight calculation, inventory, and combat therefore resolve that identity through the active composed catalog and naturally observe a scenario override. Known spells remain stable definition IDs because Realmz has no independent per-copy mutable spell state; a parallel `SpellInstance` model would add no information.

## Consequences

- Stock content is versioned and distributed once with Rebuilt.
- Campaign packages become smaller and accurately reflect original scenario ownership.
- Exact scenario overrides remain possible without resource-ID-only fallback.
- Providence and Rebuilt need an explicit application-library compatibility/hash contract.
- Scenario archives no longer repeat the application item and spell catalogs. Shared Race/Caste tables may likewise be omitted; a scenario-authored table remains an exact overlay.
- Canonical JSON entries are Deflate-compressed while already-compressed media remains stored, reducing the 13 bundled scenario archives from roughly 408 MiB to roughly 88 MiB without changing runtime semantics.
