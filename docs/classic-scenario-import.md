# Classic scenario imports

The current playable development line owns folder imports. The front door keeps the thirteen bundled Main Scenarios in their established order and lists Imported Scenarios alphabetically. Importing selects the installed revision without starting or replacing an adventure.

## Conversion and library contract

- Rebuilt runs its bundled Providence converter through a versioned JSON job interface. Providence owns startup selection, essential-file preflight, decoding, compilation, application composition, and finalization.
- Folder imports use scenario-defined races and castes when supplied, independently falling back to stock rules for an absent table. The directory picker's Import action is sufficient; no legacy menu number is required. Rebuilt explicitly supplies converter selection 20, the scenario-first branch of Castle's menu-based behavior. This applies to every folder import, including names matching bundled campaigns; it does not infer publisher or replace a Main Scenario. Cancel changes no adventure, and an ambiguous-startup retry retains the policy. The converter source and support identities are pinned in `tools/scenario-importer-inputs.json`.
- The converter captures a consistent read-only source set in disposable staging. Unknown source hashes do not affect eligibility. Hashes identify revisions and verify package and converter integrity.
- Missing critical files and undecodable essential structures reject with an actionable operation/file diagnostic. Missing optional content and authored reference defects remain exact and produce warnings; they do not require approval.
- Unknown numeric instructions follow Castle's unmatched-switch fallthrough. The import report inventories every occurrence, including unreachable records, with its source identity, native file, slot, raw/normalized opcode, operand, and Extra Code. A known instruction with unimplemented behavior remains a distinct execution-time compatibility gap. See [VM evidence](scenario-vm-evidence.md).
- Main and Imported origins remain distinct even when campaign IDs match. Imported revisions group by Providence's campaign identity, retain immutable packages, and persist a preferred revision separately. Reimporting identical output selects that revision. Saves retain their exact package binding.
- Existing schema-v3, v4, and v5 archives remain readable. V4 extends the native monster ranges; v5 preserves an imported partial `Data EDCD` tail with its candidate row ID and available byte count. Complete rows remain usable. The source fragment is preserved without invented operands, and a prepared consumer guard logs and stops a request for it before effects. The fragment's existence does not establish its authored meaning. Malformed package structure and integrity failures remain errors.
- New Classic compilation uses schema v6, retaining every native map tile value independently of rendered terrain and placed AP records. All thirteen Main Scenario baselines receive the same marker correction through Providence's canonical writer, with reversible preservation receipts. Existing installed packages and their bound saves remain available under their original identities. For each exact immediately preceding stock revision, Update Save can create a separately verified copy for the current baseline while retaining recorded progress and the original save/package; earlier revisions and imported scenarios are excluded. See the [save-copy contract](package-and-save-contracts.md) and [native marker evidence](scenario-vm-evidence.md#native-map-markers-and-placed-action-points). Third-party scenarios acquire v6 through explicit reimport.
- Rogue trap damage preserves authored signed endpoints. Castle's nonzero-low gate takes one signed range draw per target even when the high endpoint is below the low endpoint; Rebuilt uses the same shared Classic range arithmetic rather than skipping damage or rearranging the values. A zero low endpoint skips damage and its RNG draw.
- Durable import reports survive staging cleanup and conversion failure. The library index stores diagnostic summaries separately from immutable archives.

## Custom character choices

Choose the imported scenario before creating a character. Its named and usable
unnamed race/caste definitions are available directly in party setup; beginning
and ending an adventure first is unnecessary. Unnamed scenario-owned races require
a valid nonzero creation age range, and unnamed castes require positive initial
and per-level stamina dice. Eligibility-only application/template slots stay hidden.

Gameplay tables and display names are separate native inputs. A controlled Divinity
fixture found that editing custom names changed the application's global `Custom
Names` STR# 129/131 resources and left the scenario folder unchanged. Thus an absent
scenario name does not establish an unused gameplay record.

The accepted naming policy prefers resolved native names, then author-documented
helper names with a verified mapping to the exact race/caste definition. Usable
unnamed custom definitions receive `Scenario Custom Race #` or
`Scenario Custom Caste #` using Divinity's zero-based record numbers, while unused
application/template slots remain hidden. Names must not be guessed from campaign
titles, portraits, or documentation list order. Convenience labels do not change
native IDs or captured source bytes. Providence owns canonical compiled names;
Rebuilt owns creator exposure. See the [producer/consumer agreement](castle-parity-consumer-contract.md).

Reimport after a converter or source correction to create a new immutable revision.
Existing packages and saves keep their exact content and identity.

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

## Release verification

- The v6 clean Windows converter `542f9a1d250a155ca6ecf52645cca83c808c3dad` passes Rebuilt's production import task for Araman's Ring and the public package install/startup probe in isolated storage. All 72 source files remain byte-identical, and all four maps match their native signed tile words. Its 11 source warnings remain explicit. This establishes import, installation, and startup; it does not certify ordinary gameplay or packaged dialog interaction.
- `tools/scenario-importer-inputs.json` pins the GPL-3.0-or-later converter source and separately licensed stock support. The importer workflow builds native Windows, Linux, and both macOS architectures, then assembles and checks universal macOS. Runtime exports require versioned importer archive URLs and SHA-256 repository variables; missing or invalid inputs stop the export.
- The optional `sourceUpdate` supplies a hash-pinned incremental Git bundle in `tools`. The builder verifies the published base, update prerequisites and ancestry, then the final clean source tree and embedded build identity. This reproduces the v6 source correction without relying on an unpublished download URL. Publishing and accepting new native platform archives remains a separate release step; the existing platform URL variables do not update themselves.
- The same pinned source provides `providence-application-library correct-classic-map-markers <package-directory> <classic-scenarios-root> <new-output-directory>`. It preserves prior package content while adding native map values, correcting marker features, and restoring source-proven empty placed records. The output directory must be new. Retain its correction receipt and verify source identities against the bundled provenance catalog; `tools/verify_bundled_scenarios.ps1` checks the committed sanitized receipt and reconstructs each previous canonical document exactly.
- The Beta 15 local aggregate passed all 5,622 assertions across 38 suites, package alignment, provenance, architecture, maintainability, and export contracts. That checkpoint used a test-source ceiling of 11,402 substantive lines. The published clean Windows converter imported Hax through the production import task, reproduced its accepted package hash, and exposed two custom races and two custom castes in session setup without using player storage.
- The published converter source is `9281bf692dadf24863808d2474984c3e4357db33`, built with pinned Rust 1.98.1. Windows, Linux, both macOS architectures and universal assembly passed the native importer workflow. The three versioned platform archive URLs and hashes are promoted together before the runtime candidate's Verify/Export gates; a successful compiler build is separate from runtime or visible UI acceptance.

Providence's native selection R4 and whole-editor R2 flow have owner acceptance.
Retain that producer evidence separately from Rebuilt packaged import acceptance.

Remaining acceptance work:

- Run import from final packaged locations without developer tools on all three platforms, including the actual native dialog, cancellation, revision selection, and starting a working scenario. Existing app startup smoke checks do not exercise conversion.

The beta's automated results do not establish complete packaged UI acceptance or full campaign compatibility.
