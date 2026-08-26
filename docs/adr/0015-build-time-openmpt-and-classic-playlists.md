# ADR 0015: Build-time OpenMPT and Classic playlists

## Status

Accepted.

## Context

Realmz ships application-owned tracker modules and a twenty-slot Music preference model. Castle persists three states per slot: Off, Play the context title, or Continue the title already playing. Direct call sites establish Create, Items, Treasure, Shop, Camp, Temple, and Battle contexts. The pinned Castle playback and automatic map-routing functions are empty, so later source restoration is an implementation lead rather than an oracle for Outdoor, Dungeon, Indoor, Cave, Desert, Swamp, Snow, and Custom 1–3 routing.

Godot has no built-in tracker-module stream. Runtime libopenmpt would require a native GDExtension and platform-specific binaries, while the stock application bank is immutable. The pinned Outdoor file is a legacy MADG module that OpenMPT cannot decode; a later exact Castle commit replaces it with a standard MOD carrying the stock `After the Rain` title.

## Decision

Realmz Rebuilt uses OpenMPT at build time, not at runtime. A provenance-locked generator reads exact Git objects, validates every source hash, renders modules through pinned `openmpt123` settings to 48 kHz stereo float PCM, and encodes portable Ogg Vorbis. Rebuilt ships the generated Ogg bank and its source/output manifest; it does not ship OpenMPT, FFmpeg, or native decoder libraries.

Presentation owns playlist context, playback, and preference persistence. The audio presenter has separate effects and music channels beneath the existing master volume. A context mode of Play switches to and loops the selected title, Continue retains the current title, and Off stops music. The complete twenty-slot modal remains reachable from the Music menu and Preferences at both supported UI profiles. These settings never enter simulation, campaign packages, RNG, time, or adventure saves.

The stock application bank contains eleven unique modules. Playlist contexts 12–14 retain separate Desert, Swamp, and Snow preferences while resolving the Outdoor module, matching the later Castle context names and the absence of separate terrain modules in the application bank. Custom 1–3 remain scenario-owned exact music resources and resolve before stock media when Providence supplies them. Slots 18–20 remain visible and reserved. Providence schema v3 preserves Castle's separate land-level base-scale fact and explicit scenario music slots, so positive base scale selects Indoor independently of landlook and Custom 1–3 resolve only their declared package assets.

## Consequences

- Windows, Linux, and macOS exports use Godot's ordinary Ogg playback without a native plugin matrix.
- A stock music update is a deterministic asset-generation change with exact source and output review.
- Player playlist choices are application preferences and survive adventure save replacement.
- Scenario Custom music and the Indoor base-scale discriminator cross the compiler/runtime boundary explicitly rather than relying on guessed runtime compatibility.
