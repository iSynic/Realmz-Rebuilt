# Presentation settings storage

This folder owns the small host-settings repository. `SettingsRepository` loads and saves the pure `PresentationSettings` value at `user://settings.json` by default. It creates a temporary canonical JSON file, reads it back through the typed decoder, and atomically replaces the previous settings only after validation succeeds.

Settings cover display, typography, accessibility, audio, music playlists, presentation cadence, developer overlays, and the stable identity of the last successfully started campaign. They never enter gameplay saves, change Classic rules, or persist an absolute package path. Older supported schemas receive explicit safe defaults in `PresentationSettings`; malformed current data returns defaults with a diagnostic.

Start with `settings_repository.gd` for filesystem behavior and `src/game/shared/presentation/presentation_settings.gd` for the pure value and schema. The music and System presentation suites cover player-facing binding; the save/storage suites keep settings separate from playthrough state.
