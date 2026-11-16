# Per-theme interface art

Drop art here to give one interface theme its own look; no code change is needed.

- `<theme id>-tile.png`: seamless background tile, repeated without stretching.
- `<theme id>-frame.png`: neutral-grey nine-patch frame, tinted with the theme's accent.
- `<theme id>-frame-color.png`: nine-patch frame drawn in its own colours (not tinted).

Theme ids: `midnight-leather`, `slate-gold`, `slate-bone`, `slate-copper`, `slate-ice`, `ember`,
`verdant`, `arcane`, `steel`. Sizes, prompts and acceptance checks are in
`docs/features/interface-theme-art-brief.md`. Each file needs a `.json` provenance record beside it,
like `../theme-slate-tile.json`.
