# Character artwork storage

`CharacterArtImage` reads player-selected PNG, JPEG and WebP images and prepares a native 44×44 portrait or 32×32 combat icon. Fit preserves aspect with transparent padding; Crop selects an integer square; Resize fills the target square. Nearest-neighbor sampling is the default, with explicit Lanczos sampling available.

`CharacterArtRepository` preserves originals and installs content-addressed library records under `user://character-art`. Race/group names and artwork labels organize this library without changing gameplay definitions. Reimporting identical prepared pixels reuses their role-bound identity.

`CharacterArtBundle` validates selected portable PNGs, exact dimensions, hashes, metadata, payload bounds and reference closure, and implements the read-only media port. Current save v6, legacy-readable v5 and Character Files v2 embed only the images selected by their characters or creation draft. Stock-only records remain unchanged. Repository instances rooted in scratch storage use the sibling artwork library.

The app host coordinates import and admission; UI receives detached choices and textures. See [the character feature guide](../../../docs/features/characters.md#import-character-artwork) and [ADR 0021](../../../docs/adr/0021-portable-character-art.md). Run the save, Character Files, creation, appearance and session-persistence suites, then inspect import previews at 1280×720 and 800×600.
