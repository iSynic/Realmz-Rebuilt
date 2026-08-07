# ADR 0009: Put application metadata in package v2 and keep characters in an immutable vault

## Status

Accepted; implementation in progress.

## Context

The original package contract carried enough rules and world data to start a synthetic session, but not enough authored display metadata to reproduce Realmz campaign setup. A reusable character creator also needs a persistence boundary separate from an active campaign save.

## Decision

Replace the unpublished `.realmz2` schema v1 with schema v2. Providence remains authoritative and emits campaign title/version/author/contact/description, restrictions, splash identity, race/caste descriptions, and eligibility relationships. The runtime mirrors the schema hash and independently validates the new fields before building typed content.

Store reusable characters as immutable `.r2char` revisions under `user://characters/<character-id>/`. The vault repository validates untrusted records, writes through temporary readback and backup rotation, archives instead of deleting, and calculates explicit eligibility against the selected package. `GameSession` imports detached state through a typed intent and never updates the vault implicitly.

The creator is campaign-aware and presents Identity, Race & Class, Appearance, Review, and Spells. Race is the left-hand filter for available classes. Portrait and combat-icon choices are package identities; the UI must not guess local paths or silently substitute missing content.

## Consequences

- Campaign startup can explain restrictions before party creation and can show why a vault character is ineligible.
- Save data remains campaign-owned; published character revisions are portable only when all referenced stable definitions exist in the target package.
- Providence and runtime schema changes are delivered together, with regenerated synthetic fixtures and mirror-hash tests.
- Full media catalogs and every creator step still require follow-on view contracts; the current shell exposes explicit defaults rather than inventing assets.
