# Realmz Rebuilt Beta 26

You can now reach Adventure Rules from one button in party setup, without the rule description crowding the party panel. The setup, Inventory, and both HUD layouts also have more consistent screen compositions. This update corrects several uncommon Classic scenario-script paths that could stop an adventure or produce the wrong result.

[Download Realmz Rebuilt for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Extract the complete archive and keep its importer and music-importer folders with the game. This release contains desktop builds only; no Android APK is included.

## Adventure and interface changes

- **Scenario continuation:** shared Classic instruction handlers now follow the Realmz Castle codebase when authored modes fall outside a switch. They preserve earlier effects, the correct continuation, and random draws. This extends the Beta 25 fix for resting in Trouble in the Sword Lands to the same class of script behavior elsewhere; it does not alter the scenario records.
- **Additional script corrections:** Choice results, encounter returns, darkness values, monster removal, and target-independent spell effects now follow their source-backed order and state changes in the affected cases. Genuine missing content and invalid runtime state still report a failure. These focused corrections do not establish full campaign parity.
- **Party setup:** the compact Adventure Rules button opens that Settings page. Free targeting cancellation remains optional and off by default, and its rules are unchanged.
- **UI authoring:** Party Setup, Inventory and Trade, Fixed HUD, Modular HUD, and the other major screens expose their complete default arrangements in production scenes. Shared theme roles now supply consistent defaults through embedded controls while preserving the current look. This helps contributors edit the game UI; player theme selection is not included yet.

## Saves and updating

Beta 26 continues to write save v8 and read v5-v8. Character Files v2 and the bundled campaign packages are unchanged; no scenario reimport or Update Save step is needed for this release. A save made during an older, partially completed Choice or encounter operation may lack native history needed for exact continuation. If so, Rebuilt reports the missing state instead of guessing it. Keep a backup of saves and characters you care about before testing.

## Known limitations

The separate intermittent combat spellbook-input issue remains unresolved: Power Level, Choose Targets, and Abort can sometimes stop responding while Back to battle still works. Returning to battle and reopening Spells may help. If it happens, please report the scenario, caster, spell, and the actions just before it.

The optional modular HUD remains a work in progress. The fixed HUD is still the default. Including a campaign does not mean every route through it has been completed and verified.

Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml) for problems. Exact steps and a save help, but check attachments for private information before sharing them.
