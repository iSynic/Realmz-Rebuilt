# Presentation asset contract

## Purpose

Own Realmz 2 application chrome assets and their provenance.

## Ownership

- App-owned textures, verified original bitmap controls and map markers, the complete integrated Classic sound bank, proven built-in combat CIcon families, and bundled fonts used by the Classic-wide shell.
- SpriteCook, donor-commit, Castle resource-fork, Google Fonts, dimension, license, modification, and local hash provenance.

## Local Contracts

- Scenario-owned pictures, icons, portraits, sounds, and map art remain package media. Built-in resource families enter this folder only through an exact-commit catalog with explicit ownership, license, modifications, and byte hashes; scenario packages may override an exact application key.
- Verified base-game UI controls and map markers may enter only through the exact-commit catalog/importer. Preserve their source pixels and embedded labels. Record semantic evidence per asset: donor-scene use for controls or pinned Castle resource-fork ownership plus source/control-flow for built-in CICNs. A numeric resource ID without its owning fork is insufficient provenance.
- Generated chrome must contain no text, symbols, scenario content, or executable metadata. It surrounds imported controls but never repaints them.
- Command bitmap provenance is semantic, not stylistic: current donor controls remain implementation leads unless the catalog proves their Castle resource ownership. App-owned bevel, focus, and disabled chrome may unify those controls, while embedded labels remain untouched and text-only commands use live text. A generated vector reconstruction cannot be called exact without an supplied reference and explicit provenance.
- The selected SpriteCook surface remains preserved as provenance input. Runtime slate uses its deterministic cosine-feathered seamless derivative; frame centers and complete bevel bounds contain that same native-scale tile. Opposite tile edges must match exactly, no container may stretch a stone center, and generated frame corners must remain opaque.
- Original controls use nearest-neighbor filtering at exact 1x/2x only. Fonts ship with pinned source, hashes, and licenses and introduce no runtime network dependency.
- The licensed Searching atlas remains byte-exact and records its eight-frame row in the manifest. Exact Torch frame files also remain byte-exact; presentation may key only each asset's documented legacy neutral-gray matte colors while composing them onto Rebuilt chrome.
- Integrated sounds retain exact `snd ` IDs and load from Godot-imported WAV resources. The generated manifest and `THIRD_PARTY_NOTICES.txt` preserve the Castle commit, source fork, copyright, license, and decoding/resampling modification.
- Integrated combat CIcons retain exact `cicn` IDs and native dimensions. The selected catalog is limited to source-backed active cues, result effects 159–167, bounded death-effect candidates 2015–2019, and existing spell cast/resolution frames 12000–12127. Standard spells with `lookStart` zero make Castle request the absent 11992–11999 family; presentation reports that exact unavailable identity rather than substituting art. Scenario media overrides the same exact key. Red pixels or numeric adjacency alone do not establish blood, gore, or a semantic identity.
- Keep only selected production assets. Rejected candidates remain external evidence.

## Work Guidance

- Use low-contrast chrome so source art and readable text remain dominant.

## Verification

- Verify each manifest hash, dimension, semantic ID, source commit, rendering rule, and seamless edge pair against the committed file.

## Child DOX Index

- No child AGENTS.md files are currently required.
