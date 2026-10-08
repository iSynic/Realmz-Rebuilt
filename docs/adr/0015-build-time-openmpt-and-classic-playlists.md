# ADR 0015: Build-time OpenMPT and Classic playlists

## Status

Accepted.

## Context

Realmz ships application-owned tracker modules and a twenty-slot Music preference model. Castle persists three states per slot: Off, Play the context title, or Continue the title already playing. Direct call sites establish Create, Items, Treasure, Shop, Camp, Temple, and Battle contexts. The pinned Castle playback and automatic map-routing functions are empty, so later source restoration is an implementation lead rather than an oracle for Outdoor, Dungeon, Indoor, Cave, Desert, Swamp, Snow, and Custom 1–3 routing.

Godot has no built-in tracker-module stream. Runtime libopenmpt would require a native GDExtension and platform-specific binaries, while the stock application bank is immutable. The pinned Outdoor file is a legacy MADG module that OpenMPT cannot decode; a later exact Castle commit replaces it with a standard MOD carrying the stock `After the Rain` title.

## Decision

The immutable stock bank uses OpenMPT at build time. A provenance-locked generator reads exact Git objects, validates every source hash, renders modules through pinned `openmpt123` settings to 48 kHz stereo float PCM, and encodes portable Ogg Vorbis. Rebuilt ships that generated bank unchanged.

Player music uses a separate bundled import-time helper, statically linked to pinned libopenmpt, libsndfile, and their codecs. Validated MP3 and Ogg Vorbis play directly; WAV, FLAC, AIFF, MOD, XM, S3M, and IT convert to cached Vorbis. MAD remains unsupported. The game plays ordinary Godot audio streams and ships no GDExtension or FFmpeg dependency. The helper runs only for imports or explicit cache repair, in a cancellable process with bounded input, duration, output, and execution time. Its source identity and dependency licenses accompany each native export; the build recipe is in `docs/custom-music.md`.

Presentation owns music context and playback; the application host coordinates separate atomic library storage. Resolution is stable-campaign assignment, global assignment, then authored/stock music. Reusable playlists retain order, shuffle, and Repeat All/One/None. Play selects the context, Continue keeps the active queue advancing, and Off suspends it. Each campaign/context retains its queue and position for this application session; refreshes do not restart it. Shuffle uses presentation-only randomness. Missing tracks skip with diagnostics, entirely unavailable playlists fall back to original music, and no-repeat completion remains silent. Preview suspends and restores normal playback.

The Library, Playlists, and Assignments workspace remains reachable from Music and Preferences at both supported UI profiles. Managed originals are content-addressed copies independent of their original locations. Track identity includes original SHA-256 and subsong; separate tracker subsongs render without automatic repetition. Import/removal and existing volume/Classic modes apply immediately; playlist and assignment drafts use Apply/Done or Cancel. These records never enter simulation, campaign packages, gameplay RNG, time, Character Files, or adventure saves. The front-door sequence remains independent.

The stock application bank contains eleven unique modules. Playlist contexts 12–14 retain separate Desert, Swamp, and Snow preferences while resolving the Outdoor module, matching the later Castle context names and the absence of separate terrain modules in the application bank. Custom 1–3 remain scenario-owned exact music resources and resolve before stock media when Providence supplies them. Slots 18–20 remain visible and reserved. Providence schema v3 preserves Castle's separate land-level base-scale fact and explicit scenario music slots, so positive base scale selects Indoor independently of landlook and Custom 1–3 resolve only their declared package assets.

## Consequences

- Windows, Linux, and macOS exports use Godot playback and include a separately verified native import helper. macOS combines both architectures into one universal executable.
- A stock music update is a deterministic asset-generation change with exact source and output review.
- Player playlist choices are application preferences and survive adventure save replacement.
- Scenario Custom music and the Indoor base-scale discriminator cross the compiler/runtime boundary explicitly rather than relying on guessed runtime compatibility.
