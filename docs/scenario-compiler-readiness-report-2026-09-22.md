# Scenario compiler and practical-readiness batch

This report closes the 2026-09-22 compiler/readiness batch. It distinguishes source preservation, package admission, runtime containment, route proof, and full campaign certification. `loadable` means the pinned source imported, compiled, finalized, validated through Rebuilt, and started a session. It is not a claim that every route matches the Realmz Castle codebase.

## Accepted toolchain

- Providence integration branch: `fix/current-compiler-legacy-readiness` at `a779ad4de3d247b045c54e7ef4633a89a7ec9660`.
- Integrated lineages: audit base `f8735f3`, scenario media `9c1f6f3`, and application library `8bffef2`.
- Embedded source-tree identity: `d657eb1bb50a28064f5f302d9d3045904124cb7c`; the build reports `sourceDirty: false`.
- Rebuilt lock SHA-256: `c02eef95cf1e0b9b41157b558c47f14427abefdf6c355dae67fc49d25f61a987`.
- CLI SHA-256: `6c2f7c2271a5a0467b0ab62bbbb9293a720f518107e2a37ecd896b008bec7d1d`.
- Native adapter SHA-256: `98f475fde553930f4bc8340275640ebbc2d390f134dcb1112b559e9d0976646b`.
- Application-library/slimmer SHA-256: `6ed672916322d41a2fa17eb22e0ddda7c80bd30625756559ffea4828b6e797d3`.
- Schema SHA-256: `05ced7b000683f53e6220b9ac8f7d41c801e7e2c78c874287c2ae694b585273d`.
- Application package hash: `82b8718f183bb07135ca0438d833c534754e16361314759b83e5192ccb55cbad`.
- Bundled intake report SHA-256: `5a11ab3a79e34774d85ef8ec2ccaa6b06132d13ebc42dbe102bad511cdc800ba`.
- Private intake report SHA-256: `30a5ea391cd5cd860f0c0336c33c6d53eb9599d414470acb7edca054bcb2bcd7`.

The tracked lock contains no machine path. An ignored local configuration supplies the external immutable build and source-library roots. The resolver verifies every executable's bytes and embedded identity plus every application input before intake; a supplied commit or path is only an assertion against that lock.

## Bundled corpus

The designated source snapshots for all 13 bundled scenarios completed import, full diagnostic/readiness pagination, compilation, finalization, package validation, and native session startup. Four are `ready`; nine are `ready-with-warnings`. These regenerated packages are external audit artifacts and do not replace the shipped bundle in this batch.

| Scenario | Source-tree SHA-256 | Outcome | Regenerated package hash |
| --- | --- | --- | --- |
| Assault on Giant Mountain | `b61fae14575e27a1e6ee3c3262fbc2dba57237f857c08edac4e2008770927c5f` | loadable; 1 warning | `d73f3a35bcfcdcd8412c9d804c387a1db9f7c9bcfef9507281e6ad7f2457c69a` |
| Castle in the Clouds | `f54a111a39e9384c45a90ce7138615e75b6a6e830efa8ffdc9006b19e79e7356` | loadable | `b7b237e137389391eb4fc392f900ce13b46c96c873f701e383ad75303b547d39` |
| City of Bywater | `0475f7c4ddfb891d1487ba05337ef6de2a1336478565c69fe629d3c9c39172b4` | loadable; 7 warnings | `9b1616c5c0518f9ea1da07d3d792a00fd92e321d4195228fceda070bf0537740` |
| Destroy the Necronomicon | `b3ab25c0cd216b06db6d4345f9c67beeae20ad1eb19d637284944e0cd1cd737c` | loadable; 1 warning | `4dfb13fda2c8c80cb717f293f37ace52d93ebdeb18ff6d2e468ab0c15b2d12ae` |
| Grilochs Revenge | `6522528b6b1abf20f2416bc3ac41c979b506eda6f451642b9d2957c839e9b032` | loadable; 3 warnings | `6c94a1d469de20c35438c6c1e092fe04ff3069d722f7974fcc63525c743715a0` |
| Half Truth | `90b7f0b51e9c4fd6097b0413e79c031bf89a12cbef6d740cc681c5bf1871878f` | loadable | `6463050705af060d8c92863f7e94f08317889311972a94329d8350ac81904196` |
| Mithril Vault | `d351cb67b8e205350a796841ff550a44915f7638395dec5ea88dabbfc791a895` | loadable; 8 warnings | `d8dfdaab6378d2202d1176074d7978fc577b8f2bbdad2ced6874cb39458c4a6f` |
| Prelude to Pestilence | `b125e2cd0adcbfdcb1b160b0a4455650a9c4ee5714ebe29fac192ed2b1796df2` | loadable | `2c1041cc3332ca170ac9bb2218bad8978f512c9175cfbae187eb81c55e45ba71` |
| Trouble in the Sword Lands | `37323a206ea0daf412502fabdd76fa426f1920c5e75a6effd6018dcfe783de71` | loadable; 5 warnings | `92c84e993aac344d6ca8b04bcd3de042f7314371abd707333126b0865f79b15c` |
| Twin Sands of Time | `688fef4c7a390f3f36f3a60ed2f205e0f157f5b806d0ba751eb622dec7b0675d` | loadable; 3 warnings | `e1972a35f377538d4a31f59a0dc2099d0b3859742c5c9de44f112cbaf54f41f2` |
| War in the Sword Lands | `50dee61551c4f0c01ab1140eed021a3c292efda3b71a12041b3c8bf7f0891105` | loadable; 6 warnings | `11604ae0c55e22d5381cfe956567dc1e573a51ecef9ab79709499e70e7b76b9c` |
| White Dragon | `a424392bd2830fea27cb8732036572f354269c494fca9090d726fd719f0a2b81` | loadable; 3 warnings | `e85cf46e98f01b8f88190b30671e139d4b09345c13c5bbacceba097fe308e5fd` |
| Wrath of the Mind Lords | `2f534111ee7e9274eaec7ab7160b7d754dce643e0a374a6cf45a79db9317556d` | loadable | `72abc19f2496a5983d6235c0b1de1a7e57c40c33e73a1f13e5e247a1a7f459da` |

## Private corpus

Six of the 12 local third-party sources are admitted and installed through the ordinary immutable `user://packages` path. Existing package revisions were retained, including two revisions each for Araman's Ring and Lachis. The public 13-scenario allowlist and release exports are unchanged.

| Scenario | Source-tree SHA-256 | Outcome | Installed package or exact blocker |
| --- | --- | --- | --- |
| Araman's Ring | `45fd49a3668b26c8e18cc9a03ccb3d1ec530fecbd896e53bdbf08355e507c587` | loadable; 11 warnings | `405a5980bb50aec448ad0a2754155e55689c69720cbe9e4981921860d92337a0` |
| Begining of the End | `5bcba50c11ed2feabef895ddca16437702be1527dafc7bd36ff6739ace99d94d` | blocked; 4 warnings | 2,078 unresolved special-land media references prevent essential topology output; the 232-byte `Data SD2` tail and off-map rectangles are preserved, not interpreted. |
| City of Port Hyrtin | `a6586ffad8cdd29167d5e6ac5c40a146e97da084b0574bdbfdd02345096ae5fc` | loadable | `87701dfb99d0fd10ed386fe9ae950f840c2556287db285a5970229685f0f5203` |
| Dagger of Shine | `948fe215dfff3f5bb4d9181290741dede237db7debba3b36a085bd1b06bca50e` | blocked | Reachable monster `monster:-1:141` declares seven attacks over five native rows. |
| Elemental Strife | `62f86a6254289ed71c86da67b9993f94096428fa56b96cd4dcdeee84d621a15b` | blocked; 32 warnings | Layout places essential `land:3` more than once. |
| Hax | `995202e98c92aa9f788e885df17c9889f507ad9533a778f887458c17b0749a89` | loadable; 3 warnings | `53ac1cccccecbf796cc0c94cb7a32e9ab8929a49534b41da83c8adc443c17f2b` |
| Journey into the Mire | `39755b3464392a861c685bbb767e3c9daaf52b136b5a791958cc11dbcd3b379b` | loadable | `5f7e6b45c85f6316d7a9e3c95713a73a11900475db1aad0fe9d9d6c0c8114f52` |
| Kalypso's Island | `6d5110e2288d0f66d2c9630c5cbaa37765b09a60442f6711ca8b4faeac3ff836` | loadable; 6 warnings | `e68049d6948d566b7963423dd16c7bb24eb1d49dd2bd589609d5ddee09a5eb4f` |
| Lachis | `8186227fd787c137f6f9c95c3d6b8b2e077efb6b7267705a11dcafa7b7a8962e` | loadable; 1 warning | `022fa5c8dd0d594beff5cc1c836b324102981a6c1fe58d6d91a766acb709311d` |
| Search for the Lost City | `d0b646bef86bca8f889f414e21f56774a0c95a3317188dc464ed44dd54bc4ef1` | blocked | Reachable battle 3 grid slot 129 requires absent normal monster 130. |
| Spires of Steel | `278f7df54e0ad58c1e34889654c3e938a8c169efb3b90ad0f52104734f791bcb` | blocked; 21 quarantines | Placed Land 1 AP 34 contains unsupported raw opcode 173. |
| Trial by Fire | `80d34b378afdd16c6ee87bcc069130db9bd4cfaae02f30f14125a217683a8516` | blocked | Reachable XAP 98 contains unsupported raw opcode 2823. |

## Shared corrections and acceptance boundary

- Providence now reports one truthful embedded build identity from the CLI, native adapter, and application-library tool. A caller cannot relabel a stale executable with a newer commit.
- Imported readiness has three outcomes: `ready`, `ready-with-warnings`, and `blocked`. Freshly authored projects remain strict.
- Complete imported records and exact operands are preserved. Valid native targets omitted by dependency selection remain compiler-preservation failures, not warnings.
- Optional unavailable targets can remain deferred. Unsafe optional records such as wholly off-map random rectangles are retained in Providence source truth, omitted from runtime output, and named as quarantines.
- A trailing fixed-record fragment remains source evidence and is not decoded as executable data without a source-backed format rule.
- Rebuilt recognizes the deferred-reference capability, shows it during campaign selection, and invalidates older decoded-package receipts/caches through decoder 8.
- If play selects unavailable deferred data, the owning consumer fails; the session records campaign, program, slot, opcode, operands, and target, rolls back the attempted transaction, blocks continued play and saving, and leaves Load Saved Adventure and Main Menu available. An unused bad branch does not prevent an otherwise valid route.

## Verification receipt

- Providence `cargo test --workspace --all-targets` passed at `a779ad4`; its compatibility lane also passed, including 216 compatibility-focused core tests and deterministic application-library reconstruction.
- Rebuilt's final Tier 3 aggregate passed 4,771 assertions across 30 suites, Providence/package alignment, application media and music validation, architecture and maintainability ratchets, Windows/Linux/macOS export contracts, the 13-scenario bundle check, 101 differential-evidence cases, 69 Classic workflow records, and the gameplay-parity inventory.
- Focused post-refactor checks passed 642 assertions across the game-session and Scenario VM suites. The test-source ceiling remains frozen at 10,371 substantive lines, and the architecture-overhaul counters remain zero.
- The accepted toolchain resolver reverified lock digest `c02eef95cf1e0b9b41157b558c47f14427abefdf6c355dae67fc49d25f61a987`, executable hashes and embedded identity, application inputs, and reference-catalog identities before the corpus runs.

## Evidence boundary and next queue

- Compiler preservation: established for every emitted package in this batch, including the previously repaired opcode-33 XAP/encounter-result interpretation and opcode-44 loaded-Complex context coverage.
- Runtime behavior: established for warning admission, strict packages, exact missing-media distinction, selected deferred-reference containment, save blocking, restore recovery, and main-menu close. Existing opcode suites retain payment, branch, result-offset, caller-context, AP-retention, and continuation coverage.
- Route proof: this batch establishes package startup and prepared consumer fixtures only. It does not add ordinary-travel proof for every warning path.
- Ordinary campaign certification: not established for any newly admitted private scenario and unchanged for the bundled certification program.

The ranked next work is to adjudicate the six private hard blockers in this order: essential Begining topology ownership, Dagger battle 205 in a controlled Castle fixture, Elemental's duplicate Layout placement, Search battle 3's missing monster source, then the raw Spires 173 and Trial 2823 words. Warning-path probes should follow only where they can establish an observable Castle result; warning admission and fault containment already allow unrelated routes to be played.
