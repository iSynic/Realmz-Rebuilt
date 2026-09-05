# Character Files storage contract

## Purpose

Own immutable Character Files revisions, campaign eligibility facts, and the provenance-pinned Classic starter catalog.

## Ownership

- `CharacterVaultRepository` owns untrusted `.r2char` enumeration, readback-verified publication, current revision selection, archive, recovery, and empty-vault seeding.
- `CharacterVaultRecord` owns the typed external revision envelope and revision hash.
- `CharacterVaultEligibility` compares detached character references with application-plus-campaign catalogs without changing them.
- `ClassicStarterCharacterCatalog` validates the six generated starter records and their source provenance.

## Local Contracts

- Character Files are immutable revisions; importing creates a playthrough-owned detached copy.
- Every path component, record identity, provenance field, and revision hash is validated before exposure.
- Publishing and seeding are transactional. A partial starter party is never visible, and any existing vault entry suppresses seeding.
- Eligibility reports missing or incompatible race, class, item, spell, portrait, tactical-icon, level, and restriction facts without substituting content.
- The application library and starter catalog are trusted only after their committed identities and hashes match.

## Work Guidance

- Keep filesystem mutation here and campaign admission in the playthrough character workflow.
- Preserve `.r2char` fields, revision hashing, and the stable user directory unless an explicit migration is designed.

## Verification

- Run `tests/infrastructure/test_character_vault_repository.gd` and the character import workflows after changing this boundary.

## Child DOX Index
