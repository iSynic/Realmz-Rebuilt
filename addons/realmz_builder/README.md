# Realmz Builder

Realmz Builder is an editor-only map from a visible Realmz screen to the files that maintain it. Open a registered major scene and the dock identifies the surface, offers the six required preview profiles, and links to its feature guide, binding controller, detached view model, and owning test.

The profiles are Wide, Compact, Empty, Long Content, Unavailable, and Error. Selecting one adds only an ownerless editor helper; saving the scene cannot serialize that helper. A converted scene may implement `apply_editor_preview(profile)` and `clear_editor_preview()` so the dock can pass representative detached data through the same binding method used in production.

The registry distinguishes recognition from completion. `productionBinding: false` means the scene is known but still lacks a representative production-bound preview. Change it to `true` only with the matching fixture, tests, and Wide/Compact editor evidence. The architecture gate counts only those completed previews.

This entire folder is excluded from Windows, Linux, and macOS exports and has no runtime initialization path.
