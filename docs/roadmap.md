# Realmz Rebuilt roadmap

Realmz Rebuilt is a working deterministic Realmz runtime in Godot 4.7.1. Beta 1 is public; the current priority is certifying the human-centered architecture update, not feature expansion. Structural architecture work is complete; the update remains blocked until the repository is proven approachable by an unfamiliar maintainer and the exact candidate is exercised through ordinary play and protected native builds.

This page records current state and next work only. Detailed parity counts come from the generated [Classic workflow status](classic-application-workflow-status.md) and [gameplay parity status](classic-gameplay-parity-status.md). Architecture ownership comes from [the system manifest](system-manifest.json). Historical preparation remains in private Git recovery archives rather than the public roadmap.

## Current evidence

- Godot import, main-scene smoke, and all 4,030 assertions across 28 suites pass.
- The architecture-overhaul gate reports zero oversized files, functions, and top-level classes; zero cross-object private calls and generic preload aliases; zero missing scenes and production-bound previews; zero placeholder shell-mode scenes; and zero missing, undeclared, or loose-root feature files.
- Every declared feature root has a public `README.md`. The system manifest names its guide, entry points, public interfaces, tests, and performance probes.
- Stable major UI hierarchy is authored in scenes. Realmz Builder exercises all registered surfaces with Wide, Compact, Empty, Long Content, Unavailable, and Error profiles through the production binders.
- The latest complete visual gallery contains 148 Wide/Compact frames and has passed the current manual layout review.
- Test source is 8,951 substantive lines against 63,668 production lines, or 14.06 percent against the fixed 20-percent ceiling.
- The exact thirteen bundled scenarios, six generated Classic starter characters, application library, media, licenses, export exclusions, schemas, 101 differential cases, 69 Classic workflows, and eight host workflows pass their local validators.
- A tracked-files-only clean checkout completed first import, startup, the complete test suite, architecture checks, scenario validation, and every Builder preview.
- A locally sanitized one-root Git/LFS rehearsal and a separate no-local clone both passed. This proves the construction workflow, not GitHub-hosted archives.
- A Windows export was built, inspected, and smoke-launched. The exact final candidate must still be rebuilt and launched on Windows, Linux, and macOS.
- Three warmed completed-tree samples pass the local startup, movement, dungeon, combat, package, canonical-frame, and native-frame limits against the same-machine pre-migration baseline. The exact Windows candidate also passes native smoke, export-size, and peak-memory comparison.

## Architecture-update blockers

### Maintainer acceptance

- Run the hint-free [New Builder's Trial](maintainer-acceptance.md) with Samuel or another Godot contributor who has not learned the answers privately.
- The participant must locate and explain fatigue movement, character state, portable item resolution, one scenario opcode, Inventory layout, and combat Auto flow using only the public repository.
- Repair every misleading name, unrecognizable scene, missing link, or folklore dependency found during the exercise, then repeat the affected journey.

### Ordinary-play acceptance

- Complete the release-candidate walkthrough at 1280x720 and native fullscreen.
- Exercise scenario selection, empty-vault starter installation, existing-vault no-op, exploration, darkness and LOS, 2D and 3D dungeon movement, combat, Treasure, Inventory, Spells, services, maps, save, quit, and restore.
- Cover Assault on Giant Mountain, War in the Sword Lands, and City of Bywater. Record scenario, location or battle, renderer, save/package identity, and any observed defect.
- Smoke the Mobile renderer and the explicit `--rendering-method gl_compatibility` fallback.
- No P0 or P1 startup, corruption, package, crash, progression, or platform-launch defect may remain.

### Native and hosted acceptance

- Rebuild and smoke-launch the exact candidate on Windows, Linux, and an actual macOS runner.
- Require the platform export manifest, clean launch log, correct package inventory, and source revision for every artifact.
- Push the sanitized single-root `main`, enable Git LFS objects in GitHub archives, and protect the branch after check names exist.
- Validate both a fresh Git/LFS clone and GitHub Download ZIP. Every `.realmz2` must be a valid package, never an LFS pointer.
- Leave a failed public build visible and fix it with focused commits; do not tag until all required public checks are green.

## Feature work after Beta 1

### Gameplay fidelity

- Select future scenario and application work from the generated parity inventories, prioritizing missing and partial workflows before deepening already functional cases.
- Use Castle source or a controlled Castle runtime fixture only when the discrepancy, risk, compiler loss, or target-campaign ambiguity justifies archaeology.
- Preserve serialized IDs, deterministic RNG order, source-backed resource identity, and scenario-before-application overlay lookup.

### Presentation

- Keep the Classic-wide shell and supported Compact composition coherent as new workflows arrive.
- Add stable layout to scenes and variable records to exported row/card scenes. Retain algorithmic map, battlefield, dungeon, and effect rendering in their named presenters.
- Treat Builder previews and ordinary gameplay as complementary evidence: editor readability does not replace runtime acceptance, and screenshots do not replace scene ownership.

### Authoring and packages

- Keep Providence as the canonical scenario authoring/compiler system and `.realmz2` packages as immutable runtime inputs.
- Add no runtime legacy importer or arbitrary in-process GDScript scenario fallback.
- Keep application-owned Realmz content in the application library and scenario-owned content in package overlays with exact-key replacement only where Castle proves it.

## Update sequence

1. Finish the maintainer, ordinary-play, and native-platform gates above.
2. Create and verify a new final private `git bundle --all` outside the repository without replacing the retained Beta 1 archives.
3. Synchronize the existing public staging checkout from the explicit source manifest on a review branch; preserve its sanitized root and published history.
4. Run the complete gate and a separate clean LFS clone from that synchronized branch.
5. Push the review branch, wait for every protected Windows, Linux, and macOS verification/export check, and merge with linear history only after review.
6. Select the next prerelease version with the project owner; never move or reuse `v0.1.0-beta.1`.
7. Let the new exact tag workflow build Windows ZIP, Linux `tar.gz`, macOS ZIP, and `SHA256SUMS` into a draft prerelease.
8. Review every asset, launch record, license, scenario, starter character, checksum, known limitation, and save-compatibility warning.
9. Publish manually as a prerelease, download every published asset, and repeat checksum and native-startup verification.

The architecture update is complete only after every blocker above has direct evidence. A passing local suite or a plausible release artifact is not a substitute for the remaining human, gameplay, platform, and hosted checks.
