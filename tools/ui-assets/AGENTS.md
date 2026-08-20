# Classic UI asset tooling contract

## Purpose

Own deterministic import and derivation of Realmz Rebuilt application chrome and integrated Classic media.

## Ownership

- The exact-commit Remake bitmap-control and Castle resource-fork map-marker catalog and importer.
- The complete app-owned Classic `snd ` catalog, shared Data ID item `cicn` set and unidentified substitutes, plus selected source-backed battle `cicn` families decoded from the pinned Castle `The Family Jewels` resource fork.
- Deterministic selected-surface preservation, seamless runtime tile derivation, tiled nine-patch derivation, and alpha-cropped exploration-rail reduction.
- Deterministic typography import and reference rendering, including exact Mac resource-fork `FONT` 1601 decoding into a Godot BMFont descriptor/atlas, pinned Castle/Open Font License font-byte synchronization, Samuel-outline/Castle-advance reference TTF generation, approved Pencil-contour/Castle-advance/Grenze-utility runtime TTF generation, and reproducible transparent Theldrow design sheets.
- Deterministic import of the licensed Realmz intro GIF into a bounded half-size, timing-preserving application loop with an offline-verifiable frame manifest, plus deterministic derivation of its generated ornamental frame.

## Local Contracts

- Import only entries listed in `catalog.json`, from the recorded commit, through Git object data rather than a source checkout's working files. Remake controls copy exact PNG bytes. Castle CICNs are decoded from the pinned owning resource fork by resource type and ID, with both resource-fork and output hashes validated. Each entry may override its semantic evidence label, repository, commit, path, note, and classification without weakening byte provenance.
- The source checkout is read-only and supplied explicitly by the caller; never commit a machine-specific source path.
- Preserve imported pixels byte-for-byte. Derived slate surfaces must identify their source asset and algorithm.
- Search keeps exact built-in CICN 128 as inactive control-state evidence and imports the licensed eight-frame Searching row from its exact donor commit for runtime matte-keyed composition. Area Search keeps generic built-in CICN 129/130 as pressed/released control-state evidence and uses the licensed non-commercial Realmz eye/label bitmap from its exact tracked donor commit. Catalog records must preserve those distinctions and the license boundary.
- Integrated media keeps exact Classic `(resource type, ID)` identity and provenance. The runtime resolves scenario package media before these application fallbacks, matching Castle's resource-chain precedence.
- Preserve existing Godot `.import` sidecars for retained catalog assets so exact-byte regeneration does not churn stable resource UIDs; newly added assets receive their sidecars from the ordinary Godot import pass.
- `export-classic-theldrow.ps1` must preserve the pinned FONT strike's source locations, offsets, advances, ascent, descent, and leading. It may map MacRoman codes to Unicode for Godot lookup, but it must not trace, interpolate, kern, or restyle the glyphs. `remetric-classic-theldrow.ps1` may change only the pinned Samuel TTF's horizontal advances and required checksums, using that exported strike as the metric authority. `sync-fonts.ps1` reads the clean pinned Remake source through Git object data, validates every remote/source hash before replacing committed outputs, and emits the complete multi-source manifest.
- `build-classic-surfaces.ps1 -RebuildFromCommittedSurface` is the offline path for regenerating the seamless tile and frame kit without replacing selected SpriteCook provenance. Raised and inset frames tile the selected slate through their complete bounds; bevel corners remain opaque so controls cannot reveal unrelated parent colors.
- `build-exploration-rail.ps1` alpha-crops one explicitly selected SpriteCook source and reduces it to the manifest-recorded 48x468 production rail without inventing additional ornament.
- `import-realmz-intro.ps1` accepts only the approved source GIF hash, validates its 640x608/124-frame shape, halves each spatial dimension with nearest-neighbor sampling, groups four source delays per output frame, and records every output hash. The external source path never enters committed metadata.
- `build-intro-frame.ps1` accepts only the manifest-pinned 1024x1024 SpriteCook source hash, clears the measured neutral center without touching the gold fillet, crops the exact alpha bounds, and derives the 512x512 transparent-center production frame. Keep the raw generated candidate outside version control.
- `build-theldrow-font-sheet.py` validates the committed FONT 1601 descriptor/atlas and remetricked vector hashes before producing an unlabelled transparent native sheet, an unlabelled transparent vector sheet, a Unicode cell map, and a readable specimen under ignored `artifacts/font-sheets/`. The sheets are design references and never replace runtime font assets.
- `extract-pencil-theldrow.py` converts only explicitly labelled Pencil glyph exports into sorted Unicode geometry; `theldrow-modernized-glyphs.json` is the reviewed, portable source because `.pen` documents are editor-owned. `build-theldrow-modernized.py` combines those A-Z/a-z contours with exact FONT 1601 advances and pinned Grenze Gotisch utility glyphs. `sync-fonts.ps1` installs only the hash-pinned FontTools wheel, enforces all input and output hashes, and must not copy its temporary dependency tree into runtime assets.
- Validate hashes and PNG dimensions before replacing committed outputs.

## Work Guidance

- PowerShell scripts resolve the repository root from their own location and fail on the first error.

## Verification

- `sync-classic-ui-assets.ps1` verifies source commits, source hashes, decoded CICN identity, PNG bytes, dimensions, and manifest output.
- `build-classic-surfaces.ps1` verifies every generated PNG, records deterministic SHA-256 values, produces a tile with exact matching opposite edges, and records the opaque-bevel algorithm version.
- `build-exploration-rail.ps1` reports the source crop plus source/output SHA-256 values; the committed manifest records those values and production dimensions.
- `verify-classic-application-media.ps1` verifies unique IDs/resource keys, the expected integrated sound, item-CIcon, and combat-CIcon counts, generated-chrome paths/dimensions, and every committed byte count and SHA-256 without requiring an external Castle checkout.
- `verify-classic-application-media.ps1` also verifies the complete font manifest, source/commit/license fields, required Classic roles, committed paths, and byte hashes.

## Child DOX Index

- No child AGENTS.md files are currently required.
