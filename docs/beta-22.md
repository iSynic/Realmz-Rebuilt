# Realmz Rebuilt Beta 22

Beta 22 fixes throwing weapons, held keyboard commands, sound backlogs, and missing dungeon wall sections. You can also restore missing starter characters without replacing the characters already in your vault.

[Download Realmz Rebuilt for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Extract the complete archive and keep its importer and music-importer folders with the game. This release contains desktop builds only; no Android APK is included.

## Combat and exploration fixes

- **Throwing weapons work through Fire Weapon.** Equipped weapons now use their authored effects and targeting shapes instead of being limited to the physical bow-style path. Poison Throwing Daggers and Dart of Frost select a combatant; Shuriken selects an area and creates its ground effect. The shared path retains charges, range, visibility, defenses, and action costs. These three reported weapons were exercised through the visible targeting and firing controls; this is not a claim that every ranged weapon has been individually tested.
- **Held keyboard commands repeat.** Hold R for Rest or H for Heal. With Classic keyboard shortcuts enabled, hold A for Area Search. Releasing the matching key stops the command; repeat events do not build a queue of missed actions. F remains the separate continuous Search toggle.
- **Sounds no longer pile up behind movement.** Repeated water footsteps and other nonwaiting cues use the rotating sound channels, overlapping or replacing earlier sounds rather than continuing through a long backlog after you stop. Explicit completion-waiting cues retain their ordered behavior.
- **Solid dungeon boundaries beside archways.** Fixed missing wall sections that could expose gaps in the first-person dungeon view, including the reported Trouble in the Sword Lands layout.
- **Area Search is easier to find in Settings.** Controls > Keyboard & Mouse > General now lists Area Search as Hold A and identifies its Classic-shortcuts requirement. The Classic exploration reference also describes the hold.

## Restore missing starter characters

Character Files now offers **Restore starter characters**. It adds missing compatible copies of the six original Realmz 7.1.2 starters, including when old characters cannot be repaired.

The action backs up an existing vault before adding anything, preserves existing characters, revisions, and archives, and verifies each new copy after writing it. It does not convert old characters or change your saves or current party. Already available compatible starters are skipped.

## Updating and known limitations

The bundled campaigns, save format, and Character Files format are unchanged from Beta 21. No scenario reimport or save conversion is required. Back up characters and saves you care about before testing.

The intermittent combat spellbook-input issue remains unresolved: Power Level, Choose Targets, and Abort can sometimes stop responding while Back to battle still works. Returning to battle and reopening Spells may help. Please report the scenario, caster, spell, and preceding actions if it recurs.

Cancelling throwing-weapon targeting currently spends no charge or movement in Rebuilt. This differs from the Realmz Castle codebase, which consumes the charge before targeting and charges movement for aborting. The normal firing path was checked against that codebase and exercised in isolated Rebuilt fixtures; a controlled side-by-side Castle runtime comparison and exhaustive weapon coverage remain separate work.

The optional modular HUD remains a work in progress. The fixed HUD remains the default. Beta 21's typography, Settings, and combat-feedback improvements are retained.

Windows x86_64, Linux x86_64, and universal macOS archives are supplied with SHA256SUMS. Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml) for problems; a save and exact reproduction steps help.
