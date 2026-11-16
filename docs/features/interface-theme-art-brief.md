# Phase 4 art brief: interface theme textures and frames

Generated art replaces the first-pass procedural art without code changes. Save each file into
`src/ui/shared/assets/ui/themes/` under the name given here and the game picks it up on the next
launch. Remove the file to fall back to the shared art.

## What the game expects

| Asset | File name | Size | Rules |
|---|---|---|---|
| Background tile | `<theme id>-tile.png` | any square size; SpriteCook's native 200×200 works. Fine grain can be 64; planks or stones need 128 or more | Seamless on all four edges. Repeated at 1:1, never stretched. Opaque. |
| Tinted frame | `<theme id>-frame.png` | square: 64, 128 or 192 | Neutral greys on transparency. White becomes the theme accent, darker greys become darker accent. |
| Painted frame | `<theme id>-frame-color.png` | square: 64, 128 or 192 | Final colours on transparency. Not tinted. Wins over the tinted frame if both exist. |

Frame layout (nine-patch): the corners are the outer 5/16 of the width (20 px of 64, 40 of 128,
60 of 192). Everything between two corners is an edge and is stretched along its length, so an
edge must look the same along its whole run: no knots, gems or lettering in the middle of an
edge. The centre is not drawn and should be fully transparent.

Rules for all generated chrome (from the assets contract): no text, letters, numerals, symbols,
logos or scenario content; pixel art drawn at native size, crisp edges, no anti-aliased blur,
no baked drop shadow (the game adds its own shadow).

Theme ids: `midnight-gold`, `slate-gold`, `slate-bone`, `slate-copper`, `slate-ice`, `ember`,
`verdant`, `arcane`, `steel`.

## Palette reference

| Theme | Backdrop | Surface | Accent | Mood |
|---|---|---|---|---|
| Midnight Gold | `#0a0f14` | `#15222f` | `#ddba6a` | deep blue night, antique gold |
| Slate (Gold, Bone, Copper, Ice) | `#0b0e10` | `#151a1e` | `#ddba6a` / `#d8d2c2` / `#e0894b` / `#7fc7d9` | dark cut stone |
| Ember | `#120d0b` | `#1e1613` | `#e0894b` | forge, charred wood, coals |
| Verdant | `#07100c` | `#0f1d17` | `#c6d77e` | old forest, moss, bark |
| Arcane | `#0b0a16` | `#151327` | `#b9a2ff` | night sky, star chart, velvet |
| Steel | `#0b0e10` | `#151a1e` | `#7fc7d9` | brushed plate, rivets |

Tiles sit under a 45% wash of the backdrop colour and an edge vignette, so they should be drawn
a little lighter and higher in contrast than the final look. Keep the tile's average brightness
low (about 20–30%) so text panels stay readable.

## Background tile prompts

Shared lead-in for every tile:

> Seamless tileable texture, top-down, flat even lighting, 16-bit era pixel art, limited palette
> of 8–12 colours, no objects, no text, no symbols, no border, no vignette, fills the whole
> square, edges wrap perfectly.

Then add one of:

- **ember** — "charred dark timber planks with faint orange ember glow in the cracks, near-black browns `#120d0b` to `#3d2b23`, sparse `#e0894b` pinpoints"
- **verdant** — "dense dark moss over old stone, deep greens `#07100c` to `#22392d`, a few pale lichen flecks `#c6d77e`"
- **arcane** — "midnight indigo velvet with a faint woven diamond weave and very sparse tiny stars, `#0b0a16` to `#2e2a4c`, star flecks `#b9a2ff`"
- **steel** — "brushed dark gunmetal plate with fine horizontal grain and subtle wear, `#0b0e10` to `#2c363d`"
- **midnight-gold** — "dark navy leather with a fine pebbled grain, `#0a0f14` to `#2a3f4d`, no stitching"
- **slate-*** (optional replacements for the current stone tile) — "dark cut slate with fine natural cleft lines, `#0b0e10` to `#2c363d`"

## Frame prompts

Shared lead-in for a tinted frame:

> Ornamental rectangular UI panel border for a fantasy RPG, pixel art, drawn in neutral greys
> only (white highlights, mid-grey body, dark-grey shading) on a fully transparent background,
> empty transparent centre, square canvas, the border hugs the canvas edge, four identical
> mirrored corners, straight plain edges between corners with no ornaments along them, no text,
> no symbols, no drop shadow.

Then add one of:

- **metal** (Slate Gold, Slate Copper, Steel) — "bevelled metal bar about 4 px thick with square riveted corner plates"
- **flourish** (Slate Bone, Slate Ice, Arcane) — "single fine hairline with small scrolled filigree corners curling inward"
- **forged** (Ember) — "hammered wrought-iron band with chunky forged corner brackets"
- **vine** (Verdant) — "thin twig border with a small leaf knot at each corner only"
- **gilt** (Midnight Gold) — "slim double-line gilt border with small fleur corner pieces"

For a painted frame, replace "drawn in neutral greys only" with the theme's accent and surface
colours from the table and save it as `-frame-color.png`.

## Acceptance checks

1. Tile: place four copies in a 2×2 grid; no seam is visible at the joins.
2. Tile: under a 45% wash of the backdrop colour, body text `#e3e8ea` stays readable on it.
3. Frame: the centre and everything outside the border are fully transparent.
4. Frame: stretched to 400×150 and 150×400 as a nine-patch, the edges show no smearing and the corners keep their shape.
5. Frame: the outer 5/16 corners contain all ornament; edges are uniform along their length.
6. No text, letters, numerals or recognisable symbols anywhere.
7. A provenance `.json` sits beside each file (provider, generation or asset id, label, source hash, any derivation, production size and hash), following `src/ui/shared/assets/ui/theme-slate-tile.json`.

## After adding a file

Open the game, choose the theme in Settings › Display, and check Saved Adventures, the save
editor, Character Files and party setup at 1280×720 and 800×600.
