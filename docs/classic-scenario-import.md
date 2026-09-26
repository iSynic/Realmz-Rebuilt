# Classic scenario imports

The current playable development line owns folder imports. The front door keeps the thirteen bundled Main Scenarios in their established order and lists Imported Scenarios alphabetically. Importing selects the installed revision without starting or replacing an adventure.

## Conversion and library contract

- Rebuilt runs its bundled Providence converter through a versioned JSON job interface. Providence owns startup selection, essential-file preflight, decoding, compilation, application composition, and finalization.
- The converter captures a consistent read-only source set in disposable staging. Unknown source hashes do not affect eligibility. Hashes identify revisions and verify package and converter integrity.
- Missing critical files and undecodable essential structures reject with an actionable operation/file diagnostic. Missing optional content and authored reference defects remain exact and produce warnings; they do not require approval.
- Unknown numeric instructions follow Castle's unmatched-switch fallthrough. The import report inventories every occurrence, including unreachable records, with its source identity, native file, slot, raw/normalized opcode, operand, and Extra Code. A known instruction with unimplemented behavior remains a distinct execution-time compatibility gap. See [VM evidence](scenario-vm-evidence.md).
- Main and Imported origins remain distinct even when campaign IDs match. Imported revisions group by Providence's campaign identity, retain immutable packages, and persist a preferred revision separately. Reimporting identical output selects that revision. Saves retain their exact package binding.
- Schemas v3 and v4 remain readable. Imported values outside v3 monster ranges use v4; an imported partial `Data EDCD` tail uses v5 with its candidate row ID and available byte count. Complete rows remain usable. The source fragment is preserved without invented operands, and a prepared consumer guard logs and stops a request for it before effects. The fragment's existence does not establish its authored meaning. Malformed package structure and integrity failures remain errors.
- Durable import reports survive staging cleanup and conversion failure. The library index stores diagnostic summaries separately from immutable archives.

## Verification boundaries

The local forty-folder corpus is private test input, never an eligibility list. Import/export, installation, session initialization, exercised gameplay, and campaign completion are separate outcomes.

The current verification checkpoint includes:

- 454 assertions across package, imported-library, preservation, installation, conversion-task, save, and picker suites.
- 975 assertions across the combat and scenario VM suites.
- A repeat City of Bywater conversion with identical package and complete ZIP hashes.
- Before/after hashes showing no changes to any of the corpus's 1,601 source files.
- 979 Rust tests across the core, native adapter, application library, and package archive suites; the archive's seven tests were rerun after the final schema-v5 inspection correction. The runtime package suite passed 218 assertions, the focused instruction-preservation suite passed 23, and the scenario VM suite passed 601. These are focused checks, not an aggregate release acceptance.
- Export/schema mirror, architecture dependency, and architecture overhaul checks passed with the EDCD changes.
- An isolated Godot MCP Pro fixture that ran the converter and installer, reported warnings, selected the existing imported revision on reimport, retained fourteen rows (thirteen Main plus one Imported), and left the adventure stopped. The folder-selection callback was injected; this is not native-dialog interaction or clean packaged acceptance.

Private evidence is retained under the local `classic-import-corpus-20260925` evidence root. The final EDCD release-converter run converted all 40 folders, including Hax; all 40 passed ordinary installation and session initialization. The 39 previously successful package hashes remained unchanged, and Hax's release package matched its independent debug-converter result. `edcd-final-corpus/results.json` and `edcd-final-install-report.json` record those separate outcomes; `edcd-final-preservation-receipt.json` confirms all 1,601 source files remained byte-identical.

Hax's 24,636-byte `Data EDCD` divides into 2,463 complete ten-byte slots and six trailing bytes at candidate row 2463. A static scan of all 15,600 instruction slots found no reference to that candidate, including opcode 92 companion reads (`hax-edcd-reference-audit.json`). This does not establish that every complete slot is intentional Extra Code. The end region contains `Offset`, `Opacity`, `Shadow `, and three `8BIMaPAR` signatures; the six-byte fragment is ASCII `adow ` followed by a newline. Adobe documents `8BIM` as a Photoshop resource signature, so unrelated graphics/parameter residue is plausible, but its provenance and exact onset are unconfirmed. Some instructions reference complete slots in that region; only the six-byte candidate is established as unreferenced. `hax-edcd-tail-content-audit.json` retains the byte offsets and references. Import preserves the bytes and prepares a guard for an incomplete read without guessing a truncation boundary. Hax also exposed native-zero Simple Encounter choices, which Castle treats as eliminated; those now import without invented result programs. These installation/startup results do not establish safe execution of every authored branch.

Dark Portal retains native resource labels containing NUL characters in its package JSON. Godot warns and replaces those characters when constructing runtime strings; source and archive bytes remain intact. `nul-label-audit.json` records this unresolved resource-label decoding/presentation gap. Successful session initialization does not establish ordinary gameplay or campaign completion.

The graphics-signature comparison uses Adobe's [Photoshop file-format specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/), which defines `8BIM`; it does not identify Hax's specific `aPAR` blocks or establish how they entered the scenario file.

## Remaining delivery gates

- Provision the versioned Windows, Linux, and universal macOS importer archives and their repository URL/SHA variables. Build/release scripts enforce bundle integrity and platform architecture, but configured assets are a separate prerequisite.
- Run import from final packaged locations without developer tools on all three platforms, including the actual native dialog, cancellation, revision selection, and starting a working scenario. Existing app startup smoke checks do not exercise conversion.
- Wire Providence's native editor to its installed finalization support automatically; the explicit service context alone does not prove that editor workflow.
- The owner-approved Beta 12 test-source ceiling is 11,402 substantive lines; other architecture, suite-size, and maintainability limits remain unchanged.

The folder-import implementation is not release-accepted until these gates are closed. No corpus installation receipt establishes full campaign compatibility.
