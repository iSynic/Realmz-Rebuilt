# Realmz Rebuilt Beta 27

You can continue through the affected death and revival scripts without a completed death macro being dispatched again. Field spells and scrolls also select party members and retained allies at the correct power, with clearer feedback for each recipient.

[Download Realmz Rebuilt for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Extract the complete archive and keep its importer and music-importer folders with the game. This release contains desktop builds only; no Android APK is included.

## Adventure changes

- **Death-macro continuation:** fixes the repeated dispatch exposed by the centipede encounter in Trouble in the Sword Lands and Jhalor Fireblade's immediate revival macro. Completed effects remain in the event history without scheduling the same macro again.
- **Field targeting:** learned spells and scrolls with variable character counts now follow the Realmz Castle codebase. With six party members, power ×6 selects the whole party without a picker; ×7 includes all retained allies as well, regardless of how many allies are present. Combat targeting is unchanged.
- **Field spell feedback:** condition spells identify each recipient in the narration well, with the corresponding sound and party portrait effect, then append a compact party/ally count. Retained allies receive their own named feedback and sound.

## Saves and updating

Beta 27 continues to write save v8 and read v5-v8. Character Files v2, the application library, and bundled campaign packages are unchanged. No scenario reimport or Update Save step is needed. Existing saved party-only spell selections remain readable and expand only after the complete response validates.

Keep backups of saves and characters you care about. Older, partially completed Choice or encounter operations may lack native history needed for exact continuation; Rebuilt reports that missing state instead of guessing it. Beta 27 does not read save v9. Retain a v8-or-earlier save if you later test a version that writes v9 and want to return to this release.

## Known limitations

The separate intermittent combat spellbook-input issue remains unresolved: Power Level, Choose Targets, and Abort can sometimes stop responding while Back to battle still works. Returning to battle and reopening Spells may help. Please report the scenario, caster, spell, and the actions just before it.

The optional modular HUD remains a work in progress; the fixed HUD is still the default. These repairs do not establish whole-VM parity or certify every route through the bundled campaigns. Beta 27 preserves the current execution implementation; the planned VM replacement is separate work.

Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml) for problems. Exact steps and a save help, but check attachments for private information before sharing them.
