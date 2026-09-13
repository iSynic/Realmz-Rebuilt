# Presentation settings storage contract

## Purpose

Own persistence for host presentation preferences outside gameplay saves.

## Ownership

- `SettingsRepository` owns canonical JSON load, temporary write, typed readback, and atomic replacement.
- `PresentationSettings` under `game/shared/presentation` owns the pure schema, defaults, and migrations.

## Local Contracts

- Settings never enter `GameState`, `.r2save`, deterministic rules, or scenario packages.
- Malformed data yields explicit diagnostics and safe defaults rather than a partially decoded value.
- Save commits only after the temporary file decodes successfully.
- Persist stable campaign identity only; never persist an absolute package path.
- Schema 14 adds typed controller bindings, prompt-family selection, independent stick dead zones with release hysteresis, and UI repeat timing. Schemas 1–13 migrate to controller defaults without changing their established values.

## Work Guidance

- Keep filesystem APIs in the repository and preference meaning in the pure settings value.
- Preserve supported schema migrations and player-visible defaults when adding a field.

## Verification

- Run the System and music presentation suites after changing settings persistence or schema binding.

## Child DOX Index
