# Realmz Rebuilt Beta 23

In Beta 23 the bundled campaigns play closer to the originals. A wrong click no longer ends a scene: you just choose again. Save files are also sturdier.

[Download Realmz Rebuilt for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Extract the complete archive and keep its importer and music-importer folders with the game. This release contains desktop builds only; no Android APK is included.

## Campaigns play closer to the originals

- **Complete scenario records.** All thirteen bundled campaigns now carry their complete native records: dormant programs, timers, script return state and every fixed slot. Scenarios therefore behave as authored, even in rarely visited corners.
- **Map icons and scenario artwork are back.** Native map icons display again, and scenario-specific artwork replaces stock art where the original scenario did.
- **Trouble in the Sword Lands payment refusal.** The authored refusal when you can't pay (XAP 330) is restored.
- **Clock and combat fixes.** These cover the signed clock, scripted fumbles, combat relocation and nested timers. Field damage feedback now plays after its sounds and portrait effects.

## Fewer dead ends

Sometimes you answer a prompt with something it can't accept: a wrong Yes/No or list choice, an invalid ally, fumble or Safe choice, a Treasure or level-up step it can't take, or an invalid target for a field spell, scroll or item. The game now turns that answer away and lets you choose again. Before, some of these ended the scene. A failed item use keeps its charge, and a Shop Trade completes only together with the shop's refreshed stock.

## Controls and accessibility

- Start closes the Pause menu, and the D-pad moves within it.
- Icon-only command buttons expose their names and tooltips to screen readers.
- Exploration is faster: map scrolling, line of sight and interface updates do less work.

## Saves and updating

Beta 23 writes a new save format (v7) and still reads Beta 22 saves. **Beta 22 and earlier betas can't open saves written by Beta 23,** so back up saves you care about before you start.

All thirteen bundled campaigns changed. When you load a Beta 22 save, choose **Update Save**. It writes a separately named copy for the new campaign version and leaves your original save, its backup and the old campaign untouched. A few limits:

- A save made in the middle of a battle can't be updated. Finish the battle in Beta 22 first.
- A few rare pending-script states are refused rather than guessed at.
- Update Save needs the earlier campaign package that the previous beta installed in your data folder.
- Saves from the original Half Truth release (before its artwork repair) and from before the Mithril Vault, Trouble in the Sword Lands and Twin Sands of Time shop restorations can no longer be updated.

Character Files are unchanged. Saving is also more robust: an interrupted save backup now recovers instead of locking the slot, and settings and receipts are replaced without deleting the previous copy first.

## Known limitations

The intermittent combat spellbook-input issue from Beta 21 has not been resolved. Power Level, Choose Targets and Abort can sometimes stop responding while Back to battle still works. Returning to battle and reopening Spells may help. If it happens again, please report the scenario, caster, spell and the actions just before it.

The optional modular HUD remains a work in progress, and the fixed HUD is still the default.

Windows x86_64, Linux x86_64, and universal macOS archives are supplied with SHA256SUMS. Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml) for problems; a save and exact reproduction steps help.
