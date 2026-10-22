# Realmz Rebuilt Beta 24

You can make higher-power offensive scrolls, equip weapons reliably during combat, and adjust the combat text to suit you. Temporary combat effects now count down at the proper round boundary. There's also an optional rule for cancelling targeting without losing the resources you haven't used yet.

[Download Realmz Rebuilt for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Extract the complete archive and keep its importer and music-importer folders with the game. This release contains desktop builds only; no Android APK is included.

## Combat and scroll fixes

- **Higher-power scrolls:** offensive spells such as Flame Spikes now offer the legal scroll-making powers, with the correct cost for each. Being unable to cast a spell outside battle no longer locks its scroll-making power to x1. Addresses [#15](https://github.com/iSynic/Realmz-Rebuilt/issues/15).
- **Equipping during battle:** fixed the Inventory route that could leave an enabled Equip button doing nothing. Ordinary equipment changes retain their existing rules and costs. Addresses [#17](https://github.com/iSynic/Realmz-Rebuilt/issues/17).
- **Temporary effect durations:** restored the missing round processing behind buffs lasting far longer than intended. The round boundary also resumes correctly after scripted interruptions and save/load. Addresses [#18](https://github.com/iSynic/Realmz-Rebuilt/issues/18).

## Combat text your way

Under **Settings > Pacing**, choose Floating or Stationary combat text, adjust its size, and change its travel distance and vertical placement. The live preview lets you try the settings before applying them. Addresses the feedback in [#16](https://github.com/iSynic/Realmz-Rebuilt/issues/16).

## Optional free targeting cancellation

**Free targeting cancellation** is a new per-adventure option in party setup and **Settings > Adventure Rules**. It is **off by default**.

With it enabled, cancelling before committing restores reserved spell points, scrolls, or item charges and does not charge movement. That includes thrown-weapon charges reserved when you enter targeting. It does not undo an attack or spell you've already committed.

With it off, cancellation keeps the Classic behavior, including the charge and movement costs. This is the optional rule discussed in [#19](https://github.com/iSynic/Realmz-Rebuilt/issues/19), rather than a change to the default rules. You can change it outside battle when no action or interaction is pending.

## Settings and the footer

- Pause > Settings now opens the full editor directly. All eight categories are available, including Adventure Rules, with Sound & Music separate from Pacing.
- Character Art is under Interface > Artwork; the music library remains under Sound & Music.
- Search no longer changes the footer layout when toggled. With command titles hidden, it keeps the same compact width as Area Search.

## Saves and updating

Beta 24 writes save format v8 and reads v5-v8. **Earlier betas cannot open saves written by Beta 24.** Back up saves you want to keep using in an older build.

Beta 23 saves retain their campaign revision and load without a campaign update for this release. Older saves start with Classic cancellation rules. Character Files v2 and the bundled campaign packages are unchanged; this release does not expand Update Save eligibility for earlier campaign revisions.

## Known limitations

The separate intermittent combat spellbook-input issue remains unresolved: Power Level, Choose Targets, and Abort can sometimes stop responding while Back to battle still works. Returning to battle and reopening Spells may help. If it happens, please report the scenario, caster, spell, and the actions just before it.

The optional modular HUD remains a work in progress; the fixed HUD is still the default. Including a campaign does not mean every route through it has been completed and verified.

Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml) for problems. Exact steps and a save help, but check attachments for private information before sharing them.
