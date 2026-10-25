# Realmz Rebuilt Beta 28 — opt-in test release

You can help test the new scenario runner by continuing an existing adventure, playing encounters and scripted battles, and saving and restoring along the way. Beta 28 replaces the execution machinery behind those scripts while keeping the existing campaigns and their compiled data.

This is an opt-in prerelease. **Beta 27 remains the Latest release and the fallback.** Before testing, back up saves and characters you care about and retain an untouched v8-or-earlier save.

[Downloads for Windows, Linux, and macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Choose Beta 28 explicitly, extract the complete archive, and keep its importer and music-importer folders with the game. This release contains desktop builds only; no Android APK is included.

## Adventure changes

- **One scenario runner:** branches, encounters, battle and death macros, timers, and application scripts now share explicit execution and return state, following the Realmz Castle codebase. This replaces the overlapping execution paths behind the recurring continuation bugs.
- **Save and restore:** suspended scripts retain their exact pending interaction and next execution phase. Restoring does not replay completed effects or reroll decisions.
- **Combat responsiveness:** combat-account display updates are combined within a frame, and hidden account text is rendered when shown. This reduces handoff work without changing combat decisions, event order, or random rolls.
- Beta 27's death-macro continuation and field-spell targeting and feedback repairs are retained.

## Saves and returning to Beta 27

**Beta 28 writes save v9 and reads v5–v9. Beta 27 cannot read v9.** Loading an older save does not rewrite it; saving in Beta 28 writes the new format. Keep an untouched original if you want to return to Beta 27.

Both versions use the same existing local data folder. Extracting Beta 28 into another directory does not give it separate saves or Character Files. Back up those files before testing and work from copies of saves you want to preserve.

Character Files v2, the application library, bundled scenario archives, compiler, and scenario package formats are unchanged. No scenario recompilation, reimport, or Update Save step is needed for this replacement. Existing package bindings and the previously approved Update Save routes remain unchanged.

Older suspended operations can lack native history needed for exact continuation. Rebuilt reports unavailable history instead of guessing it. Save v1–v4 and Character Files v1 remain unsupported.

## What to test and report

Continue an existing adventure and try new ones. Encounters, scripted combat, death and revival, timed events, and saving and restoring while a prompt is open are especially useful. If something that worked in Beta 27 now fails, please report it as a regression.

Use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml). Include the beta version, operating system, scenario, exact steps, and an original save from before the problem when possible. Check attachments for private information before sharing them.

## Known limitations

The separate intermittent combat spellbook-input issue remains unresolved: Power Level, Choose Targets, and Abort can sometimes stop responding while Back to battle still works. Returning to battle and reopening Spells may help. Please report the scenario, caster, spell, and the actions just before it.

The optional modular HUD remains a work in progress; the fixed HUD is still the default. Verification covers the documented execution, restoration, legacy-save, and campaign-caller cases. It does not certify every route through every campaign or establish whole-VM parity.
