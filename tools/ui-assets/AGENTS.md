# Classic UI asset tooling contract

## Purpose

Own deterministic import and derivation of Realmz Rebuilt application chrome and integrated Classic media.

## Ownership

- The exact-commit Remake bitmap-control and Castle resource-fork PICT/CICN/color-cursor catalog and importer.
- The complete app-owned Classic `snd ` catalog, shared Data ID and target-campaign stock-supply item `cicn` sets and unidentified substitutes, plus selected source-backed battle `cicn` families decoded from the pinned Castle `The Family Jewels` resource fork.
- Deterministic selected-surface preservation, seamless runtime tile derivation, tiled nine-patch derivation, alpha-cropped exploration-rail reduction, and provenance verification for the ImageGen exploration-stage surround.
- Deterministic typography import and reference rendering, including exact Mac resource-fork `FONT` 1601 decoding into a Godot BMFont descriptor/atlas, pinned Castle/Open Font License font-byte synchronization, Samuel-outline/Castle-advance reference TTF generation, approved Pencil-contour/Castle-advance/Grenze-utility runtime TTF generation, and reproducible transparent Theldrow design sheets.
- Byte-exact import of the project-owner-supplied Realmz Rebuilt Ogg Theora/Vorbis intro and independent MP3 soundtrack with offline-verifiable media metadata, plus deterministic derivation of its generated ornamental frame.
- Deterministic extraction of stock Realmz application text from pinned resource-fork `STR#` records. Application text never enters scenario packages.
- Deterministic build-time OpenMPT rendering of the exact stock Realmz tracker modules into portable Ogg Vorbis, with a pinned source catalog and runtime manifest.

## Local Contracts

- Import only entries listed in `catalog.json`, from the recorded commit, through Git object data rather than a source checkout's working files. Remake controls copy exact PNG bytes. Castle CICNs and color cursors are decoded internally; Castle PICTs are decoded through the caller-supplied pinned decoder path. Source-fork and output hashes are validated by resource type and ID, and color-cursor hotspots are validated before import. Each entry may override its semantic evidence label, repository, commit, path, note, and classification without weakening byte provenance.
- The source checkout is read-only and supplied explicitly by the caller; never commit a machine-specific source path.
- Application-media regeneration replaces only the catalog-owned `sounds`, `item-icons`, and `combat-icons` directories. It must preserve separately generated stock music and any future sibling media banks under `classic-media`.
- Preserve imported pixels byte-for-byte. Derived slate surfaces must identify their source asset and algorithm.
- Search keeps exact built-in CICN 128 as inactive control-state evidence and imports the licensed eight-frame Searching row from its exact donor commit for runtime matte-keyed composition. Area Search keeps generic built-in CICN 129/130 as pressed/released control-state evidence and uses the licensed non-commercial Realmz eye/label bitmap from its exact tracked donor commit. Catalog records must preserve those distinctions and the license boundary.
- Ordinary Encounter imports exact application PICT 180 from the pinned Family Jewels fork. The committed source image remains intact; presentation isolates its yin-yang while recomposing the command on Rebuilt chrome. The source-proven blank Heal CNTL is not fabricated into an exact asset; its project-owner-supplied app glyph remains provenance-manifested and presentation samples only its exact non-transparent bounds without resampling.
- The exact party marker catalog contains Castle CICN 175 west, 186 east, and 178 camp plus aboard CICN 13300/13400 variants for source-present landlooks 0, 3, 5, 6, and 7 from the pinned owning resource fork; importer output must retain their native 32×32 pixels and semantic identities.
- The exploration pointer catalog contains exact Castle `crsr` 138–146 plus their authored hotspots. Land uses all nine party-relative regions; top-down dungeon travel uses the four cardinal members.
- Integrated media keeps exact Classic `(resource type, ID)` identity and provenance. The runtime resolves scenario package media before these application fallbacks, matching Castle's resource-chain precedence.
- The integrated item-icon catalog includes exact Family Jewels CICN 6195; verification requires it so the identified Battleaxe +2 application fallback cannot regress to a blank image.
- Preserve existing Godot `.import` and `.uid` sidecars for retained catalog assets so exact-byte regeneration does not churn stable resource UIDs; newly added assets receive their sidecars from the ordinary Godot import pass.
- `export-classic-theldrow.ps1` must preserve the pinned FONT strike's source locations, offsets, advances, ascent, descent, and leading. It may map MacRoman codes to Unicode for Godot lookup, but it must not trace, interpolate, kern, or restyle the glyphs. `remetric-classic-theldrow.ps1` may change only the pinned Samuel TTF's horizontal advances and required checksums, using that exported strike as the metric authority. `sync-fonts.ps1` reads the clean pinned Remake source through Git object data, validates every remote/source hash before replacing committed outputs, and emits the complete multi-source manifest.
- `build-classic-surfaces.ps1 -RebuildFromCommittedSurface` is the offline path for regenerating the seamless tile and frame kit without replacing selected SpriteCook provenance. Raised and inset frames tile the selected slate through their complete bounds; bevel corners remain opaque so controls cannot reveal unrelated parent colors.
- `build-exploration-rail.ps1` alpha-crops one explicitly selected SpriteCook source and reduces it to the manifest-recorded 48x468 production rail without inventing additional ornament.
- `import-rebuilt-intro.ps1` accepts only the approved OGV and MP3 hashes and byte lengths, copies both byte-for-byte, and records the fixed 832x480/24-fps/5.167-second Theora/Vorbis video plus 30-second stereo MP3 contract. Metadata permanently mutes embedded OGV audio and declares the click-enabled MP3 loop independent from video playback. External source paths never enter committed metadata.
- `build-intro-frame.ps1` accepts only the manifest-pinned 1024x1024 SpriteCook source hash, clears the measured neutral center without touching the gold fillet, crops the exact alpha bounds, and derives the 512x512 transparent-center production frame. Keep the raw generated candidate outside version control.
- `build-theldrow-font-sheet.py` validates the committed FONT 1601 descriptor/atlas and remetricked vector hashes before producing an unlabelled transparent native sheet, an unlabelled transparent vector sheet, a Unicode cell map, and a readable specimen under ignored `artifacts/font-sheets/`. The sheets are design references and never replace runtime font assets.
- `extract-pencil-theldrow.py` converts only explicitly labelled Pencil glyph exports into sorted Unicode geometry; `theldrow-modernized-glyphs.json` is the reviewed, portable source because `.pen` documents are editor-owned. `theldrow-modernized-rules.json` records the reviewed production sheet's shared cap, x-height, ascender, descender, cap-height figure, width, sidebearing, collision, mixed-case optical-weight, and ink-density rules. `build-theldrow-modernized.py` combines those A-Z/a-z contours and rules with exact FONT 1601 advances and pinned Grenze Gotisch utility glyphs. It may transform or optically embolden glyphs only as declared by that rule file, must retain zero kerning, and must not change line measure. Numerals retain their exact Castle advances while the declared figure zone normalizes their vertical extent. `verify-theldrow-modernized.py` validates the complete rule set—including raster-equivalent mixed-case weight and figure height—against the built TTF before installation. `sync-fonts.ps1` installs only the hash-pinned FontTools wheel, enforces all input and output hashes, and must not copy its temporary dependency tree into runtime assets.
- Validate hashes and PNG dimensions before replacing committed outputs.
- `sync-classic-application-music.ps1` reads only exact Castle Git objects listed by `application-music-catalog.json`, requires the catalogued OpenMPT and FFmpeg versions, validates source bytes and hashes before decoding, and emits only the eleven application-owned stock tracks plus their manifest. The legacy pinned Outdoor MADG stays recorded as evidence; only the exact later standard-MOD replacement may be rendered. The generator may remove stale `playlist-*.ogg` files only inside the resolved stock-music destination.

## Work Guidance

- PowerShell scripts resolve the repository root from their own location and fail on the first error.
- Application-text generators must produce byte-identical UTF-8 output under both Windows PowerShell 5.1 and PowerShell 7; do not rely on host-specific `ConvertTo-Json` formatting or escaping.

## Verification

- `sync-classic-ui-assets.ps1` verifies source commits, source hashes, decoded CICN identity, PNG bytes, dimensions, and manifest output.
- `build-classic-surfaces.ps1` verifies every generated PNG, records deterministic SHA-256 values, produces a tile with exact matching opposite edges, and records the opaque-bevel algorithm version.
- `build-exploration-rail.ps1` reports the source crop plus source/output SHA-256 values; the committed manifest records those values and production dimensions.
- `verify-classic-application-media.ps1` verifies unique IDs/resource keys, the expected integrated sound, shared/stock-supply item-CIcon, and combat-CIcon counts and required stock-supply identities, intro-video and independent-soundtrack provenance/playback contracts, SpriteCook and ImageGen chrome plus status/command-glyph provenance, paths, dimensions, and every committed byte count and SHA-256 without requiring an external Castle checkout.
- `verify-classic-application-media.ps1` also verifies the complete font manifest, source/commit/license fields, required Classic roles, committed paths, and byte hashes.
- `verify-classic-application-music.ps1` verifies all eleven stock playlist IDs, twenty-slot manifest contract, source provenance, durations, committed Ogg signatures, byte counts, and output hashes without requiring Castle, OpenMPT, or FFmpeg.
- `sync-classic-application-text.ps1` verifies the pinned Castle commit and exact Family Jewels resource-fork hash, decodes MacRoman deterministically, emits all 252 class-one-through-three player-spell descriptions keyed by packed Classic ID, and reproduces identical bytes across supported PowerShell hosts.

## Child DOX Index

- No child AGENTS.md files are currently required.
