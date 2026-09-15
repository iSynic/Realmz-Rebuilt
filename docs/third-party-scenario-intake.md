# Third-party Classic scenario intake

This register records local compiler and runtime intake without bundling scenario payloads. A successful import, package compile, or startup probe is not a campaign-playability claim.

## Pinned lane

- Providence vNext commit: `9c1f6f33ab2ff126cb105ff0af5376353d8cd909`
- Providence adapter SHA-256: `6e08a350ea841aaeed189152e788e4b038afea917bcf31afc9829683418cd12d`
- Rebuilt commit under test: `c2c5b842`
- Rebuilt application package: `realmz-classic-application-library`, logical hash `82b8718f183bb07135ca0438d833c534754e16361314759b83e5192ccb55cbad`
- Evidence date: 2026-09-14
- Evidence lane: complete source-tree byte inventory, atomic Providence import, Rebuilt-readiness inspection, package compilation when ready, and Rebuilt public package/startup probe

The local no-clobber report retains each file hash and length. The table below records the deterministic hash of the ordered `relative path, length, SHA-256` source manifest, not a hash of a repacked archive.

## Results

| Scenario | Source files / bytes | Source-tree SHA-256 | Status | Current boundary |
| --- | ---: | --- | --- | --- |
| Araman's Ring | 72 / 518,245 | `45fd49a3668b26c8e18cc9a03ccb3d1ec530fecbd896e53bdbf08355e507c587` | conversion-blocked | One unresolved reachable-combat reference. |
| Begining of the End | 71 / 972,687 | `5bcba50c11ed2feabef895ddca16437702be1527dafc7bd36ff6739ace99d94d` | conversion-blocked | `Data SD2` has a non-256-byte tail and the atomic import refuses it. |
| City of Port Hyrtin | 68 / 1,185,556 | `a6586ffad8cdd29167d5e6ac5c40a146e97da084b0574bdbfdd02345096ae5fc` | opening-tested | Archive SHA-256 `5a8960eb1c79712eedb9eb189aaccad31a8148620cce8f6772ebc8e00eea7e84`; logical package hash `b684c976d125af8ad539ec2859dc0a354a20af4e6e4e299b9df9e65e6f15c6a2`; controller movement from land 6, 41,1 fires the opening at 41,4 and South clears all three authored acknowledgements. |
| Dagger of Shine | 71 / 1,578,037 | `948fe215dfff3f5bb4d9181290741dede237db7debba3b36a085bd1b06bca50e` | conversion-blocked | Normal monster 141 stores physical and magical attack counts of seven in every difficulty variant; land AP 3:33 calls XAP 168, which starts battle 205 and places that monster. Castle has only five stored attack rows and indexes later rows out of bounds, so no clamp or invented-row repair is yet justified. |
| Elemental Strife | 70 / 1,549,418 | `62f86a6254289ed71c86da67b9993f94096428fa56b96cd4dcdeee84d621a15b` | conversion-blocked | One unresolved reachable-combat reference. |
| Hax | 74 / 4,383,048 | `995202e98c92aa9f788e885df17c9889f507ad9533a778f887458c17b0749a89` | conversion-blocked | XAP 567 opcode 2 references unavailable message 3001. |
| Journey into the Mire | 69 / 1,066,250 | `39755b3464392a861c685bbb767e3c9daaf52b136b5a791958cc11dbcd3b379b` | opening-tested | Archive SHA-256 `53ace211a18dae91382c8da393b615beedf4f4c8a496e89dc00b81611c085bea`; logical package hash `c2794134c6993541deb313cb397f5b95625bc2cfb01d8bd4c1afbbc5df09cc9b`; controller movement from land 3, 8,64 fires the nearby chest program at 6,64 and South clears its authored acknowledgement. |
| Kalypso's Island | 73 / 1,570,235 | `6d5110e2288d0f66d2c9630c5cbaa37765b09a60442f6711ca8b4faeac3ff836` | conversion-blocked | One empty-intersection random rectangle and five unresolved reachable-combat references. |
| Lachis | 71 / 724,275 | `8186227fd787c137f6f9c95c3d6b8b2e077efb6b7267705a11dcafa7b7a8962e` | conversion-blocked | One unresolved reachable-combat reference under the current vNext compiler. This does not invalidate the separately pinned older Lachis package and route evidence. |
| Search for the Lost City | 66 / 1,368,940 | `d0b646bef86bca8f889f414e21f56774a0c95a3317188dc464ed44dd54bc4ef1` | conversion-blocked | 27 unresolved reachable-combat references. |
| Spires of Steel | 74 / 1,667,653 | `278f7df54e0ad58c1e34889654c3e938a8c169efb3b90ad0f52104734f791bcb` | conversion-blocked | 21 empty-intersection random rectangles and a reachable-combat selection failure reporting 137,391 unresolved references. |
| Trial by Fire | 64 / 1,429,212 | `80d34b378afdd16c6ee87bcc069130db9bd4cfaae02f30f14125a217683a8516` | conversion-blocked | Three unresolved reachable-combat references. |

Both packages passed strict archive validation, application-plus-scenario composition, content construction, session start, and first-view projection. Rendered isolated fixtures on Rebuilt `f5828beeef83cdbac6ad32488b94f7c0637ce62f` then exercised their actual controller owner from the pinned start coordinates. City of Port Hyrtin fixture `a4d1fa7d86e5d987a077700a3b199cab` reached message IDs 690–692 and returned to exploration; its final 1280×720 capture hashes to `7f57696ae915eaa613c1081138fd753380379a172e55a3bf08d8a14c660bb7e0`. Journey into the Mire fixture `09809063b330720a74322a9d9ab6e9a2` reached message ID 12 and returned to exploration; its final capture hashes to `eaa15f8ad9cea152287ba1a4e4c64fddb512262eae88d0837449fdabf9eee387`. Both fixtures used the same honestly recorded unrelated `project.godot` dirty fingerprint `62ddce81684286d172439b3b1dc1b6c165f481bd71a8f8fff9aecb3f221e2415`. This establishes `opening-tested`, not party-setup, save/load, broader progression, or main-route playability.

## Dagger of Shine attack-count evidence

- Source tree SHA-256 is `948fe215dfff3f5bb4d9181290741dede237db7debba3b36a085bd1b06bca50e`. Its `Data MD`, `Data MD1`, and `Data MD-1` files hash to `91ae8467dde51ac721d5800cd37afee5b1260ad73df4e8b928c6367096ff0460`, `76da563eaff9e48a281c77aa26c1d2f9b5202d3e83ccd01b35a4c333c432ddf9`, and `888cbc695602981cc0ee01715fdd514862b68892db6e05d025f6153cee3b6c85` respectively.
- Record 141 stores `attackCount = 7`, `magicAttackCount = 7`, and `bonusAttack = 0` in all three files. Each record still contains exactly five physical attack rows.
- The reference is not dead catalog data. Land `Data DD` row 333 is level 3 AP 33 at `(56,46)`, has 100-percent chance, and calls XAP 168. XAP 168 opcode 56 uses Extra Code row 415 (`205, 0, 169, 3000, 0`), which starts battle 205. `Data BD` battle 205 slot 84 contains normal monster 141.
- Pinned Castle commit `491816ad60037394f92c428e99c004494d3c28b3` declares only `attacks[5][4]` in `structs.h:162`, iterates physical attacks to `noofattacks + bonusattack` in `checkforenemy.c:126`, and indexes `attacks[attacknum]` directly in `attack.c:694-695` and `attack.c:787`. The sixth and seventh iterations therefore read adjacent struct fields, which is unsafe C behavior rather than a stable seven-row data contract.
- Current Providence correctly leaves this scenario conversion-blocked rather than silently clamping the count. The next evidence must be a controlled Castle execution of this exact battle plus a Providence decision that preserves the raw source while exposing a safe, explicit runtime meaning. Static AP reachability does not establish that an ordinary campaign reaches land level 3 `(56,46)`.

## Next executable cases

1. Inspect the single unresolved combat reference shared by Araman's Ring, Elemental Strife, and this Lachis revision before changing either compiler or runtime behavior.
2. Execute Dagger of Shine battle 205 in a controlled pinned Castle fixture, then coordinate Providence's raw-preservation and safe-projection decision; do not clamp or synthesize attacks from source inspection alone.
3. Determine whether the `Data SD2` tail in Begining of the End is a valid partial final record, unrelated appended data, or damaged source before relaxing the codec.
4. Separate authored inactive rectangles from malformed active rectangles in Kalypso's Island and Spires of Steel.
5. Generate normalized Providence feature reports for the two opening-tested packages, then begin their ordinary save/resume routes only after AOGM and War retain priority.
