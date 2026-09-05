# Adventure saves

Start with `SaveRepository` for files and `SaveEnvelope` for the stable `.r2save` representation. A write is staged, decoded and validated, backed up once, and atomically installed. A read constructs detached typed data before `GameSession.restore` may replace an active playthrough.

The neutral `SaveSlotPreview` contract under `src/playthrough/session` is the browse record returned to the host. It contains only visible campaign, party, clock, location, validity, and error facts. It never exposes a filesystem path or grants load permission by itself; the host still performs full package-bound restore validation.

```text
SessionSnapshot -> SaveEnvelope -> temporary file -> readback -> primary
                                      |
                                      +-----------> one backup

save files -> SaveRepository -> SaveSlotPreview -> System screen
```

Use `test_save_repository.gd` for file and preview behavior and `test_session_persistence.gd` for full-session restoration.
