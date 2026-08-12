# Presentation asset contract

## Purpose

Own Realmz 2 application chrome assets and their provenance.

## Ownership

- App-owned textures, verified original bitmap controls and map markers, the complete integrated Classic sound bank, and bundled fonts used by the Classic-wide shell.
- SpriteCook, donor-commit, Castle resource-fork, Google Fonts, dimension, license, modification, and local hash provenance.

## Local Contracts

- Scenario-owned pictures, icons, portraits, sounds, and map art remain package media. Built-in resource families enter this folder only through an exact-commit catalog with explicit ownership, license, modifications, and byte hashes; scenario packages may override an exact application key.
- Verified base-game UI controls and map markers may enter only through the exact-commit catalog/importer. Preserve their source pixels and embedded labels. Record semantic evidence per asset: donor-scene use for controls or pinned Castle resource-fork ownership plus source/control-flow for built-in CICNs. A numeric resource ID without its owning fork is insufficient provenance.
- Generated chrome must contain no text, symbols, scenario content, or executable metadata. It surrounds imported controls but never repaints them.
- The selected SpriteCook surface remains preserved as provenance input. Runtime slate uses its deterministic cosine-feathered seamless derivative; frame centers contain that same native-scale tile. Opposite tile edges must match exactly, and no container may stretch a stone center.
- Original controls use nearest-neighbor filtering at exact 1x/2x only. Fonts ship with pinned source, hashes, and licenses and introduce no runtime network dependency.
- Integrated sounds retain exact `snd ` IDs and load from Godot-imported WAV resources. The generated manifest and `THIRD_PARTY_NOTICES.txt` preserve the Castle commit, source fork, copyright, license, and decoding/resampling modification.
- Keep only selected production assets. Rejected candidates remain external evidence.

## Work Guidance

- Use low-contrast chrome so source art and readable text remain dominant.

## Verification

- Verify each manifest hash, dimension, semantic ID, source commit, rendering rule, and seamless edge pair against the committed file.

## Child DOX Index

- No child AGENTS.md files are currently required.
