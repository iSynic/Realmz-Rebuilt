# ADR 0014: Realmz application content ownership

## Status

Accepted.

## Context

Classic Realmz opens application resources separately from scenario resources. Stock rules, spell text, controls, fonts, sounds, PICTs, and CICNs belong to Realmz itself. Copying those records into every compiled campaign makes a scenario appear to own data it never shipped, multiplies package size, permits campaign output to erase stock presentation, and obscures Castle's exact scenario-before-application override behavior.

## Decision

Realmz Rebuilt ships one pinned, versioned stock Realmz application library. Providence campaign output contains only original scenario-owned content plus normalized references to stock identities. Scenario content can override an exact stock resource type-and-ID only when Castle source or a controlled fixture proves that resource-chain behavior.

Providence validates a campaign against the application-library contract but does not embed that library in the campaign. Rebuilt composes the two typed inputs before constructing a session. Missing stock content is a Rebuilt build/install defect; missing scenario content is a campaign readiness defect. Standard spell descriptions are the first migrated text family and resolve from the bundled Family Jewels negative `STR#` catalog by packed Classic spell ID.

## Consequences

- Stock content is versioned and distributed once with Rebuilt.
- Campaign packages become smaller and accurately reflect original scenario ownership.
- Exact scenario overrides remain possible without resource-ID-only fallback.
- Providence and Rebuilt need an explicit application-library compatibility/hash contract.
- Schema v3's duplicated stock definition tables are migration debt and cannot be expanded; the next package-contract cut removes them rather than adding compatibility aliases.
