# Realmz Builder

Realmz Builder is an editor-only map from a visible Realmz screen to the files that maintain it. Open a registered major scene and the dock identifies the surface, offers the six required preview profiles, and links to its feature guide, binding controller, detached view model, and owning test.

The profiles are Wide, Compact, Empty, Long Content, Unavailable, and Error. Selecting one adds an ownerless clone of the edited scene, then passes a deterministic detached interaction request or game view through the clone's production binder or controller. The clone, its variable row scenes, and the small profile badge have no scene owner, so saving cannot serialize any preview content or alter the scene being authored. Older registered scenes may temporarily provide `apply_editor_preview(profile)` while they move to the production-bound fixture catalog.

The registry distinguishes recognition from completion. `productionBinding: false` means the scene is known but still lacks a representative production-bound preview. Change it to `true` only when `RealmzBuilderPreviewFixtures` supports all six profiles through that scene's production binder and the owning test exercises the same fixture. The architecture gate counts only those completed previews.

This entire folder is excluded from Windows, Linux, and macOS exports and has no runtime initialization path.
