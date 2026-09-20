# Save storage contract

## Purpose

Own strict adventure-save encoding, transactional persistence, backup recovery, and detached save browsing.

## Ownership

- `SaveEnvelope` owns the versioned `.r2save` wire boundary around one `SessionSnapshot`.
- `SaveRepository` owns enumeration, strict readback, temporary writes, backup rotation, and atomic replacement.
- `HalfTruthMediaSaveUpdate` admits only the pinned Half Truth media-only archive transition after exact archive, installation receipt, application-library, and gameplay-document checks.
- The repository constructs the session-owned `SaveSlotPreview`, which carries detached browse status and visible adventure facts without exposing a path or mutable envelope.

## Local Contracts

- Treat every save as untrusted until its complete typed envelope and session snapshot validate.
- Write and read back a temporary file before rotating one backup and atomically replacing the primary.
- Browsing may classify corruption or identity mismatch, but only replacement-session restore proves that an enabled record can become active.
- Preserve schema version, stable fields, primary/backup identity, explicit incompatibility, and unchanged-current-session failure behavior.
- Save v5 requires authoritative equipped-instance order; save v1 through v4 are rejected without migration or partial interpretation.
- Save JSON retains full floating-point precision so a restored gameplay multiplier produces the same subsequent result as the unsaved boundary. Existing truncated values remain historical save state; do not infer a replacement value.
- An explicit Half Truth update writes a separately named v5 copy only after detached restoration against the current package. The original primary and backup remain untouched; a retry may accept only an identical existing copy.

## Work Guidance

- Add save wire facts to `SaveEnvelope`, file transactions here, and visible browse facts to the neutral `SaveSlotPreview` contract under `src/playthrough/session`.
- Keep UI controls, active-session mutation, and package loading out of this folder.

## Verification

- `tests/infrastructure/test_save_repository.gd` protects encoding, validation, backup recovery, mismatch classification, and previews.
- `tests/integration/test_session_persistence.gd` protects complete snapshot and restore behavior.

## Child DOX Index

- This feature has no child DOX documents.
