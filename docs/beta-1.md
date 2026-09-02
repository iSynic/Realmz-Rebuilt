# Realmz Rebuilt 0.1.0 Beta 1

Beta 1 is the first public compatibility and usability release. It is intended for testing, not irreplaceable playthroughs.

## Release acceptance

The `v0.1.0-beta.1` prerelease is published only after the exact tagged commit passes verification and native export/startup checks on Windows, Linux, and macOS. The release must contain Windows and macOS ZIP archives, a Linux `tar.gz`, and `SHA256SUMS`. Publication remains a manual owner action after inspection of the draft release.

## Candidate walkthrough

At 1280×720 and native fullscreen, validate:

- Front door, bundled-scenario selection, and package validation.
- Empty-vault installation of all six starter characters and existing-vault no-op behavior.
- Scenario start, exploration, darkness and line of sight, 2D/3D dungeon movement, combat, Treasure, inventory, maps, save, quit, and reload.
- Default Mobile renderer and an explicit `gl_compatibility` smoke.

Any startup/export failure, save or character corruption, missing/invalid package, repeatable crash, progression blocker, or platform-specific native launch failure blocks publication.

## Known limitations

- This is a beta; presentation and Classic-behavior corrections continue.
- The existing `RealmzRemake2` user-data directory is intentionally retained. Back up valuable saves and characters before testing.
- Rebuilt does not import legacy saves or authoring projects from the earlier host architecture.
- Rendering varies with GPU and driver. Use the documented OpenGL compatibility override when the default RenderingDevice path is unavailable.
- Only the thirteen listed Castle-distributed scenarios are bundled and supported by this release. Other scenarios require independently licensed Providence packages.

## Reporting a bug

Use the repository's Beta bug template. Include the operating system and architecture, renderer, scenario and package identity, coordinates or battle number, exact reproduction sequence, expected and actual result, and a minimal relevant log. A save is useful only when it contains no private information or unlicensed scenario content.
