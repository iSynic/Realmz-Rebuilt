# Scenario program preservation

This document records the historical program-restoration revision. Schema-v7 full-record preservation and current verification are defined in [Faithful scenario records](faithful-scenario-records.md); historical quarantine and endpoint counts below do not authorize current exclusions.

Classic imports preserve every complete placed AP, XAP, Simple-result and Complex-result program, including dormant and empty bodies. Reachability diagnoses potential calls; it does not select which programs survive compilation. Exact source files are retained as inert, content-addressed package assets with null resource keys.

Raw preservation, executable projection, static references, exercised gameplay and exported contents are separate results. Incomplete records retain their bytes and a diagnosis. Exact reviewed foreign battle/monster tails remain inert; their source and row hashes, boundaries and hook candidates remain visible. These quarantines are explicit safety decisions, not a claim that Castle ignored everything beyond those boundaries.

The owner-designated Bywater input remains authoritative. Its eleven changed bytes precede its byte-identical foreign monster tail; the preservation pass retains those corrections. Existing War, Prelude, Wrath, shop, marker, media and Trouble payment corrections also remain declared inputs.

The pass also restores 333 source-owned text fields across 112 Wrath item definitions (109 existing rows and three scenario-owned overrides of application placeholders) from exact scenario `STR#` resources, without changing their gameplay fields. Shared-definition comparisons account separately for retained trailing whitespace, Castle's first-NUL display boundary, malformed native strings and the approved stock fallback for Bywater's all-zero caste table. Fresh projection is comparison evidence, not automatic replacement authority.

## Reviewed program inventory

The bundled `program-inventory.json`, `program-audit-findings.json` and `program-restoration.json` record exact identities and dispositions. Counts below include empty programs; they are not counts of reachable or completed encounters.

| Campaign | Programs retained | Previously missing programs |
| --- | ---: | ---: |
| Assault on Giant Mountain | 1,349 | 543 |
| Castle in the Clouds | 1,756 | 743 |
| City of Bywater | 1,473 | 553 |
| Destroy the Necronomicon | 1,516 | 672 |
| Grilochs Revenge | 2,351 | 1,044 |
| Half Truth | 2,067 | 569 |
| Mithril Vault | 2,192 | 992 |
| Prelude to Pestilence | 1,111 | 423 |
| Trouble in the Sword Lands | 5,646 | 554 |
| Twin Sands of Time | 1,650 | 593 |
| War in the Sword Lands | 7,060 | 698 |
| White Dragon | 3,911 | 3,105 |
| Wrath of the Mind Lords | 5,095 | 731 |

The native-source annex covers 460 files, including partial records and nested source files. Six independently reviewed battle/monster ranges contain 222 inert records; none was present in the previous bundles. No program body is excluded by those ranges. Preserved unavailable resource and shop references remain authored defects and are reported separately from compiler omissions.

## Lossless source compression

Native source payloads use ZIP Deflate level 9 when every descriptor for the payload identifies validated inert Classic source bytes. Assets shared with another use retain their existing encoding. Stored predecessor archives remain supported. Every non-manifest entry, including all program bodies and source indexes, stays byte-identical; the manifest records the actual successor compiler and its resulting package hash while preserving the content identity.

`source-compression.json` records the thirteen exact predecessor/successor pairs and manifest reversal hashes. The original program inventory, findings and repair receipt remain unchanged. Verification checks the compressed endpoint before applying the historical audit checks; it never substitutes a new stamp for proof of retained content.

Build the accepted converter source from `tools/scenario-importer-inputs.json`, then build its application-library example with `cargo +1.98.1 build --release -p providence-application-library --example recompress_classic_source_assets`. Run `python tools/recompress_bundled_sources.py --baseline-root <retained-audited-bundle> --output <new-output> --compiler <built-example> --compiler-commit <embedded-source-commit>` twice into different directories and compare all outputs. `python tools/verify_source_compression.py --baseline-root <retained-audited-bundle>` checks promoted archives and metadata against the exact predecessors.

The readable `program-restoration.json` remains the maintainer source. `tools/compress_program_receipt.py` generates its complete runtime `.json.zlib` copy using its recorded generator build; `--check` validates the existing output portably, and `--check --reproduce` proves exact regeneration on the pinned build. Runtime verifies the compressed hash, decoded length and original JSON hash before parsing. Exports include the compressed copy and exclude the plain receipt and audit-only reports; release verification checks those facts in the actual PCK.

Explicit Update Save also accepts the thirteen pinned compression pairs. Historical supported updates first validate the compression reversal and then their original declared correction. The host restores unchanged state against the successor and publishes a separately named copy. Old packages, original saves, backups, pending requests, RNG, recorded faults and Quick Save targets remain intact. Unlisted revisions gain no eligibility.

## Reproduction and verification

Use explicit absolute input/output paths and new external output directories. Preserve the original bundles and provenance catalog before generating candidates.

1. Resolve the clean converter from `tools/scenario-importer-inputs.json`, including its incremental source bundle and pinned Rust toolchain. Verify the executable's embedded source identity. The independent development-tool lock retains its historical identity.
2. Build `audit_program_projection.rs` and `restore_scenario_programs.rs` as examples in that converter's native-adapter and rebuilt-package crates. The former accepts an imported project, a new projection filename and a pinned native-input descriptor. That descriptor identifies every relative native path, byte length and SHA-256 beneath its explicit source directory.
3. Run `prepare_program_restoration.py --bundle <retained-bundle> --projections <projections> --application <application-archive> --output <new-recipes>`. Restore each archive through the Providence helper, retaining its receipt and source payloads.
4. Run `audit_native_programs.py` with explicit `--intake`, `--projections`, `--bundle`, `--candidates`, `--application`, `--application-items`, `--castle`, `--castle-commit`, `--compiler-commit`, `--release-payloads` and `--output` inputs. Native records and Castle semantics supply the independent reference inventory; compiler reachability is a comparison result.
5. Run `finalize_program_audit.py --pipeline <audit-json> --candidates <candidates> --baseline-bundle <retained-bundle> --projections <projections> --text-dispositions <reviewed-native-text-evidence> --output <new-report-directory>`. Review every declared addition, shared-program change, dependency, source omission and quarantine before promotion. `audit_definition_comparison.py` inventories shared content records; the finalized findings embed its exact comparison and the independent native-text adjudication. Verification rechecks native Pascal rows, bounded `STR#` resources and restored fields against retained source bytes.
6. Promote the exact reviewed archives and three reports together with the provenance catalog and runtime receipt hash. Regenerate setup catalogs. Run `verify_bundled_scenarios.ps1`; `verify_program_restoration.py --package-root <extracted-export-archives>` also checks actual exported contents. The native release verifier performs this extraction from the PCK automatically.

Corruption probes must reject removed required programs, altered encounter ownership and stale programs carrying a current compiler stamp. Authored unavailable targets must remain distinguishable from an omitted defined target. A clean startup does not establish any of these facts.

## Existing saves and reported source faults

Packages and saves remain immutable. Update Save accepts only individually pinned predecessor/current pairs after exact archive and installation-receipt checks, reversal of the complete declared package delta, unchanged-state detached restoration and separate-copy readback. It preserves originals, backups, pending continuations, RNG, artwork, the active adventure and the Quick Save target. Existing supported marker and Trouble payment chains reverse the program delta before their own checks. Unlisted revisions retain their original package.

Trouble's XAP 923 uses random region 3 on land 10. It subsequently calls XAP 925, whose native opcode-23 instruction instead requests rectangle 24 on land 3. That later source reference is outside the native twenty-slot array; the preservation pass retains and diagnoses it. Under `FD-SCENARIO-014`, runtime skips that out-of-range mutation quietly and continues, preserving saving instead of converting Castle's unchecked write into a terminal session fault. The shared Extra Code row is also used by an opcode-7 instruction elsewhere, suggesting an authoring error, but that does not authorize changing opcode 23 to opcode 7.

Mithril XAP 410 retains its native failure target of -1. Selected imported instruction failures latch their exact VM context even when static checking could not issue a matching warning. They block further actions and saving; direct close or replacement restore remains available. Missing targets, unsafe encounter-local modes and incomplete Extra Code operands stay visible and fail when selected; the compiler does not replace them with success, continuation or fabricated definitions. These records require separate fidelity work if their ordinary routes are encountered.

Complete static accounting and representative runtime verification do not certify full campaign playthroughs. Imported third-party scenarios require explicit reimport through the corrected converter; this audit does not replace them or rewrite their saves.

## Death-macro teleport save boundary

A prepared native Bywater battle 191, alternate monster set -1, reaches restored XAP 111 through an ordinary lethal melee attack. Its opcode 37 moves the party from land 0 to land 5 (62,10) while combat remains active. Native land-0 AP 84 is also a static caller of that battle; the prepared battle is not proof of that complete route.

The save codec preserves the committed party destination and independently serialized battlefield, including terrain, actors, continuations and RNG. Content-aware restore validates both map identities and rejects an unavailable battlefield source without replacing the live session. Actual save/readback and subsequent Guard replay verify this boundary without changing teleport or combat execution.

At pinned Castle revision `491816ad60037394f92c428e99c004494d3c28b3`, `newland.c:2664-2699` changes the map and returns without explicitly ending combat; `killbody.c:115-145` resumes the combat caller. However, `loadland-loadpixmap.c:21-27` overwrites global terrain. Destination-terrain reload behavior during combat remains a separate unresolved fidelity question. This save correction neither claims that terrain parity nor assumes Castle had an equivalent combat-save format.
