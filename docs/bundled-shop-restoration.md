# Bundled shop restoration

The corrected campaigns restore shops omitted from earlier compiled packages:

| Campaign | Added shop IDs |
| --- | --- |
| Mithril Vault | 3, 5, 7, 10 |
| Trouble in the Sword Lands | 1, 5, 6, 7, 9, 14, 15, 16, 18, 19 |
| Twin Sands of Time | 2, 3, 4, 6, 7, 8, 9, 10, 11, 17, 18, 19, 20, 23, 24, 25, 26 |

These 31 definitions are referenced by 34 compiled instruction sites. All native
`Data SD` inputs match Castle commit `ef95fcff40d81f14ac668d5e13466da4a51de6f4`.
Negative opcode-6 operands already open the absolute shop identity immediately;
the repair restores missing content rather than changing that runtime behavior.

`src/storage/packages/bundled_campaigns/shop-restoration.json` pins both archive
revisions, native source hashes, the Providence revision and repair helper hash,
added-record digests, and the preexisting content/payload digests. All preexisting
definitions remain identical. Maps, scenario programs, assets, and other ZIP
payloads remain byte-identical. The unresolved Mithril battle references 814 and
20000 are outside this repair; they are not silently replaced or ignored.

## Existing adventures

Choose the corrected main campaign and open Save & Load. Eligible earlier v5
saves offer **Update Save**. This writes a separately named verified copy; choose
that copy to continue. Primary saves and backups can be updated independently.
The original save, backup, installed archive, and active session remain untouched.

The updater admits only the three exact revision pairs. It verifies both archive
hashes, the original installation receipt's application identity, and the
additive content boundary before restoring a detached session. Party and item
state, shop quantity/buyback overrides, progress, pending interactions and
continuations, and RNG must survive unchanged. Only the package hash changes in
the copied envelope. A different existing destination is never overwritten; an
identical retry is accepted. Arbitrary package mismatches and older save formats
remain rejected. No failed AP is rewound or replayed by the update: use a valid
save from before the failure and approach the repaired shop normally.

Original revisions remain discoverable as installed campaigns. Updating is
optional; a save continues to require its exact original package until copied.

## Reproduction and verification

Run `tools/restore_bundled_shops.ps1` with `-ProvidenceRoot`,
`-ClassicScenariosRoot`, `-OriginalPackagesRoot`, and a new `-OutputRoot`.
Retain the pinned original archives under their catalog filenames. The helper
builds in an isolated snapshot of Providence `a779ad4`, using its native shop
decoder, shop projector, manifest compiler and archive writer. It checks input
hashes and refuses to replace an existing shop or output. Its result must match
the accepted archive hashes. The output root retains source, build, and receipts
as reproducible local evidence; it never modifies the Providence checkout or
installs a campaign.

`tools/verify_bundled_scenarios.ps1` includes `verify_bundled_shops.py`, checking
all 225 opcode-6/51/73 shop instruction sites across the 13 bundled campaigns,
the 31 additions, and unchanged prior content. This is static preservation
coverage, not campaign completion certification.

`tools/shop_save_update_probe.gd` takes an original-package directory and a new
scratch directory after `--`. It uses isolated installs and saves to exercise
explicit updates, backups, stock state, pending shop continuations, rejection,
idempotent retries, and negative-ID entry. It never reads or writes player saves.
