# Bundled campaign contract

## Purpose

Own the Castle-distributed scenario packages that ship with Realmz Rebuilt.

## Ownership

- Immutable Providence package archives for the 13 scenarios distributed with Castle Realmz.
- One source, compiler, application-library, ownership-inventory, package-identity, byte-count, and archive-hash catalog, plus the exact owner-designated City of Bywater source manifest.

## Local Contracts

- Bundled campaigns are CC BY-NC-SA 4.0 content compiled by the pinned Providence revision in `castle-bundled-scenarios.provenance.json`. The pinned Castle revision is the default source; City of Bywater instead uses `city-of-bywater.source.json` until Castle adopts that exact snapshot.
- Package archives are immutable release inputs. Selecting one uses the same complete validation and user-owned immutable installation path as an external package; the bundle is not a trusted-package bypass.
- Scenario archives retain their complete custom item/spell tables and exact media overrides while resolving stock definitions and media from the one accepted application library. Race and Caste tables remain application-owned except for source-proven exact scenario overrides.
- Compiled worlds preserve every defined placed Action Point, including initially nonpositive dormant records that opcode 13 may enable later; blank native rows remain excluded.
- Compiled player-map records preserve their authored primary and secondary titles from the scenario `STR#` resources named `Map Names`; generic `Map N` fallbacks are not valid bundled-campaign output.
- Compiled scrolling-text `TEXT` assets preserve leading returns and every other decoded character position used by the same-ID Classic `styl` table; trimming display whitespace during package compilation is forbidden.
- Compiled land secrets preserve the underlying mapstats collision while the 3000-band marker is hidden; a colocated Action Point becomes entry-eligible only after discovery. The bundle verifier anchors this contract to City of Bywater Land 5 at 61,10.
- A valid user-installed revision takes precedence over its bundled campaign baseline in application discovery.
- Do not add commercial, user-owned, tutorial, test, template, duplicate-version, or otherwise non-distributed scenario content here.

## Work Guidance

- Regenerate packages through Providence from their pinned source manifests; never hand-edit archives or substitute the Oracle Castle copy for the designated City of Bywater snapshot.
- Owner-approved War branch corrections are recorded in `war-in-the-sword-lands.corrections.json`. Apply its revision-guarded Providence commands only after checking the pinned source hashes and original values; preserve the imported raw sources and shared settings 1153. The fidelity ledger distinguishes contextual intent from observed Castle execution.
- Update the provenance catalog and release verifier atomically with any package change.
- Keep original scenario compilation inputs in `compiler`; `acceptedApplicationLibrary` names the current runtime library verified against the unchanged scenario archives. A library-only rules correction must not rewrite scenario compiler provenance or recompile their authored content.
- The shared-atlas migration records each unchanged campaign's prior archive identity separately from its original compilation inputs. It removes only the legacy application-owned `PICT:302` copy after native ownership checks; authored documents and retained payloads remain byte-identical. War's corrected native rebuild instead records its own raw compiler output and corrections catalog. All 13 packages resolve the complete shared atlas from the application library.

## Verification

- `tools/verify_bundled_scenarios.ps1` checks the exact archive set, file bytes, SHA-256 values, manifest identities, Providence compiler and application-library revisions, scenario-only definition/media inventories, reduced combined footprint, authored player-map titles, offset-preserving scrolling `TEXT`/`styl` pairs, effective application-plus-scenario asset resolution and base-plus-overlay separation for every emitted land CICN, City of Bywater source-snapshot identity, its dormant Ranthog Action Point preservation, and its crypt-door Encounter prompt/actions.

## Child DOX Index

- No child AGENTS.md files are currently required.
