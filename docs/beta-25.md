# Realmz Rebuilt Beta 25

You can now see poison and disease damage as it happens in combat. Allies you keep after a battle also recover their weapon when the Classic rules allow it, so a fumble no longer leaves them unarmed in later fights. Resting past midnight in Trouble in the Sword Lands also continues normally.

[Realmz Rebuilt downloads for Windows, Linux, and macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Extract the complete archive and keep its importer and music-importer folders with the game. This release contains desktop builds only; no Android APK is included.

## Combat and adventure fixes

- **Poison and disease feedback:** combat now shows the condition name and damage at the affected character or monster, with the appropriate sound. Lethal damage appears before the defeat result. Reduced Motion and Skip retain the result in the combat account. This makes the existing damage visible; it does not change damage, condition durations, or random rolls. Addresses [#20](https://github.com/iSynic/Realmz-Rebuilt/issues/20).
- **Retained allies' weapons:** fixed the missing post-battle weapon recovery for surviving allies you choose to keep. Recovery follows the rules in the Realmz Castle codebase and preserves their carried loot. Addresses [#21](https://github.com/iSynic/Realmz-Rebuilt/issues/21).
- **Resting in Trouble in the Sword Lands:** fixed an item check in its daily script that could stop the adventure when resting past midnight. Load a save made before the fault to continue; no campaign update is needed. Addresses [#23](https://github.com/iSynic/Realmz-Rebuilt/issues/23).

## Startup cleanup

Closing the game during startup now releases its background load and audio cleanly. The startup check also catches the teardown warning that previously slipped through verification.

## Saves and updating

Beta 25 keeps Beta 24's save format: it writes v8 and reads v5-v8. Beta 24 saves load without a format or campaign update. Betas before Beta 24 cannot open v8 saves, so back up saves you want to keep using in an older build.

Character Files v2, bundled campaign packages, and Update Save eligibility are unchanged. Free targeting cancellation remains optional and off by default; this release does not change its rules.

## Known limitations

The separate intermittent combat spellbook-input issue remains unresolved: Power Level, Choose Targets, and Abort can sometimes stop responding while Back to battle still works. Returning to battle and reopening Spells may help. If it happens, please report the scenario, caster, spell, and the actions just before it.

The optional modular HUD remains a work in progress; the fixed HUD is still the default. Including a campaign does not mean every route through it has been completed and verified.

Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml) for problems. Exact steps and a save help, but check attachments for private information before sharing them.
