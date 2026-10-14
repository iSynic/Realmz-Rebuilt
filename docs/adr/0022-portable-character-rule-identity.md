# 0022: Portable Character Files rule identity

Status: Accepted

## Context

Comparing entire source and destination race/class records rejected stock characters when a scenario changed equipment permissions or eligibility for unrelated races. Requiring a complete source adventure package also stranded valid Character Files after package replacement.

The Realmz Castle codebase at `491816ad60037394f92c428e99c004494d3c28b3` provides the admission evidence. `src/realmz_orig/partyselect.c:625-706` checks explicit scenario restrictions and copies the decoded existing character into the party without comparing source definitions or creation eligibility. Its finalization calls `bandaid()` (`partyselect.c:383-404`), which loads the destination race/class profile (`misc.c:1651-1704,2232-2253`). Creation eligibility instead filters new-character selection (`race.c:183-205`). This is source/control-flow evidence, not a controlled Castle runtime comparison.

Castle's cleanup can raise its last special ability, clear magic for a noncaster profile, and delete items missing from the destination. Rebuilt's existing explicit possession handling and no-silent-deletion policy remain separate; this change does not claim complete parity with that cleanup.

## Decision

- Existing stock-source characters use destination race/class rules. Explicit campaign bans and limits, required definitions, item ownership/load, magic and artwork validation still apply.
- Creation eligibility and default artwork do not establish gameplay identity. Fingerprints also exclude names/descriptions, retaining every other field and ordered array exactly.
- Custom-source characters remain confined to their source campaign under Rebuilt's deliberate policy. A changed custom definition within that campaign still rejects; a matching definition in another campaign does not grant access.
- New publications include `sourceRules` version 1 inside the immutable Character Files v2 envelope and revision digest. It records only the selected race/class IDs, normalized SHA-256 fingerprints and captured custom flags. Strict decoding rejects unknown shape/version, malformed hashes, mismatched character IDs, and custom identity without a source campaign.
- The identity is captured from validated source content and reconstructs a transient admission catalog without loading an old adventure. It is part of the character's integrity boundary, not a cryptographic claim about who authored the character. No executable content or source package is embedded.
- Existing v2 records without the extension still resolve exact source packages. Missing evidence never permits a stock assumption. An explicit maintainer repair may back up the complete vault, verify historical source bytes and definitions, and publish separately hashed revisions while preserving state, provenance, artwork and originals. Runtime never migrates files implicitly.
- The player-facing Repair Character Files action applies this same explicit repair boundary to current-format current revisions. It resolves exact recorded source catalogs, or a pinned stock-only historical profile for the old application identities `d134c8f552d4e5893dcf82ea25bd21504c45a1e0cffb84bf4061a1b83ec00b49`, `35dd24b24879e6e4aa8e3eb54672dfba99ba6c1538a3b6760898fcd4a91e8589`, and `45298c295fc784b528f4219d6ceb0454cb482d894b66440e529d7763e7cb0036`, plus the stock-only Assault on Giant Mountain package `9124d092afe5afd3b3caf467ba2d329b3e8dfa3779a618c84d48b4eabb9ae6f2`. No other hash or campaign-title inference is permitted. It reviews proposed repairs and skipped records before writing; unavailable or ambiguous evidence skips that record with recovery guidance.
- Before publication, the joined worker makes and hash-verifies a complete vault backup, including history, archives and invalid files. A repair copies every original envelope/state field into a separately hashed revision, adding only validated `sourceRules` and the new revision hash; exact source custom flags remain custom. It never changes saves or the active party. The interface provides Open backup and a visible Done action. A completed write is read back and its current index verified; failure restores touched current-index selections. Any verified new revision already written remains immutable noncurrent history. Process interruption may leave a subset of valid repaired revisions beside the complete backup, so the next explicit repair can resume. This workflow does not claim global crash atomicity.
- Package and save formats do not change. Saved-party import still needs the exact source package to restore its full adventure before applying the shared admission policy.

## Verification

Run the existing Character Files, campaign picker, session persistence, shell and Builder suites. Verify repair review/cancel, complete backup inclusion and hash readback, all four pinned historical profiles, custom-scope retention, raw original-envelope preservation, index readback and write-failure rollback, and explicit resume from an interruption model. Inspect canonical and compact layouts and exercise actual UI controls through the compositor in both source and exported builds. Keep those proof modes separate from direct session admission and Castle source evidence.
