# Spell capability batch acceptance

## Scope

Adjudicated and implemented the remaining seven Classic spell capability gaps identified across raw third-party scenarios (Hax, Dagger of Shine, and Spires of Steel) against pinned Castle source:
- Special 48 Identify: Combat single-target item identification implemented for characters; marked not applicable for monsters (`DISPOSITION_NOT_APPLICABLE`) since monsters carry no inventory items.
- Special 60 SP Drain: Expanded combat SP drain to support opposed groups (target type 10).
- Special 49 Death Magic: Admitted and executable in camp/field for touch/self (target type 5).
- Physical touch (target type 5) and area (target type 3) damage spells (damage type 9): Admitted as ordinary combat spells, removing over-restrictive projectile guards.
- Special 89: Unassigned reserved opcode in Classic Realmz with no engine implementation; safely classified as not applicable (`DISPOSITION_NOT_APPLICABLE`) with explicit typed diagnostic rejection under reserved special rules.

Save, Character Files, settings, and package schemas are unchanged. No packages, player data, or Providence checkout were modified.

## Verification

- Focused test suites passed cleanly: `test_combat_flow` (317 assertions), `test_realmz_rules` (366 assertions), 683 assertions total.
- Hotspot and test-budget verification passed (`tools/verify_hotspot_test_budget.ps1`): production=69082, tests=9802, ratio=14.19%.
- Human-maintainability verification passed (`tools/verify_human_maintainability.ps1`).
- Architecture overhaul verification passed (`tools/verify_architecture_overhaul.ps1`).
- Architecture boundary verification passed (`tools/verify_architecture.ps1`).
- Spell signature denominator verified (`tools/verify_spell_signature_denominator.ps1`): 508 unique signatures across 48 scanned source entries; 495 implemented, 12 not applicable, 1 malformed-safe, 0 pending runtime gaps. Classification is not exhaustive campaign execution proof.
- Fidelity decisions documented in `docs/fidelity-ledger.md` under `FD-COMBAT-016` and `FD-COMBAT-017`.
- Code changes pass `git diff --check`.

## Remaining work

Zero pending runtime gaps remain in the authoritative spell signature denominator. Macro single-target and ray policies remain explicit safe rejection (FD-SCENARIO-009).

Campaign journeys, native execution on other operating systems, physical-controller comfort, and public release were not performed or certified by this batch.
