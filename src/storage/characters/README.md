# Character Files storage

This folder owns the external Character Files boundary. `CharacterVaultRepository` reads and publishes immutable `.r2char` revisions beneath `user://characters`, validates portable identities and exact revision hashes, rotates backups, archives revisions, and commits only after temporary-file readback succeeds. It returns typed `CharacterVaultRecord` values and never mutates an active playthrough.

`CharacterVaultEligibility` compares a detached revision with the active campaign and application catalogs. Race, class, level, item, spell, portrait, tactical-icon, and authored campaign restrictions remain explicit; incompatible content produces reasons rather than silent substitution. The playthrough layer imports an eligible detached copy through its typed party workflow.

The bundled application character library and Classic starter catalog are immutable release inputs. `ClassicStarterCharacterCatalog` validates their pinned hashes and `seed_if_empty` installs all six records transactionally only when the vault is truly absent or empty. Raw 7.1.2 converter fixtures remain under `tools/fixtures` and are excluded from runtime exports.

Start with `character_vault_repository.gd` for persistence, `character_vault_record.gd` for the wire record, and `character_vault_eligibility.gd` for campaign admission facts. The infrastructure vault suite owns transactional, recovery, seeding, and eligibility proof; character playthrough suites own the imported copy.
