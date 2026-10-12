# Presentation media

Start with `ApplicationMediaCatalog` for the complete stock library and `ClassicMediaCatalog` for the effective application-plus-scenario view. `ClassicUiAssetCatalog` translates source-backed UI roles to exact resources without making role names an ownership or fallback mechanism.

`ClassicAudioPresenter` owns disposable Godot playback nodes. `ClassicMusicCatalog` describes the stock playlist and `ClassicMusicContext` identifies the music appropriate to the current detached route and map. Simulation only requests exact cues; these presentation classes never decide whether a gameplay action occurred.

The actual source media and provenance live in `../assets`. Use the presentation system and music suites together with the application-media verifier when changing this boundary.

Player-imported character artwork arrives through a separate read-only media port with explicit content identities. It has no Classic resource key and does not change scenario-before-application lookup. Its managed bytes and portable validation belong to `src/storage/character_art`.
