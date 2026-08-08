# Presentation asset contract

## Purpose

Own Realmz 2 application chrome assets and their provenance.

## Ownership

- App-owned textures, verified original bitmap controls, and bundled fonts used by the Classic-wide shell.
- SpriteCook, donor-commit, Google Fonts, dimension, license, and local hash provenance.

## Local Contracts

- Scenario pictures, icons, portraits, sounds, and map art remain package media and never enter this folder.
- Verified base-game UI controls may enter only through the exact-commit catalog/importer. Preserve their bytes and embedded labels; scene-use evidence proves semantics without claiming unproven direct Classic extraction.
- Generated chrome must contain no text, symbols, scenario content, or executable metadata. It surrounds imported controls but never repaints them.
- Original controls use nearest-neighbor filtering at exact 1x/2x only. Fonts ship with pinned source, hashes, and licenses and introduce no runtime network dependency.
- Keep only selected production assets. Rejected candidates remain external evidence.

## Work Guidance

- Use low-contrast chrome so source art and readable text remain dominant.

## Verification

- Verify each manifest hash, dimension, semantic ID, source commit, and rendering rule against the committed file.

## Child DOX Index

- No child AGENTS.md files are currently required.
