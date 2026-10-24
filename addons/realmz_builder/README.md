# Realmz Builder

Realmz Builder is an editor-only map from a visible Realmz screen to the files that maintain it. Open a registered major scene and the dock identifies the surface, offers the six required preview profiles, and links to its feature guide, binding controller, detached view model, and owning test.

The profiles are Wide, Compact, Empty, Long Content, Unavailable, and Error. Selecting one projects representative values, variable row scenes, and command art onto the actual edited production scene. Sample rows and art have no scene owner. The plugin removes them and restores sample values before saving, then restores the selected preview afterward. Visual edits to the production scene remain yours.

The registry distinguishes recognition from completion. Every currently registered major surface is production-bound across all six profiles, except that Character creation uses one Wide state. A new registration remains incomplete until `RealmzBuilderPreviewFixtures` supports it through the production binder and reusable row scenes, the owning test exercises that fixture, and `productionBinding` is true. The editor reads the recorded production-bound snapshot because ordinary runtime scripts cannot run in the editor. Generate it with `godot --headless --path . --script res://addons/realmz_builder/generate_editor_samples.gd`, and check for drift with the same command followed by `-- --check`. The check does not write sample media and also rejects missing or unused PNGs. The application shell's ready runtime still uses `GameShell.present`.

This entire folder is excluded from Windows, Linux, and macOS exports and has no runtime initialization path.
