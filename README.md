# Realmz Rebuilt

Rebuilt is a new way to play the Classic scenarios on modern computers while keeping their maps, encounters, rules, art, and quirks recognizable. A greenfield, cross-platform Realmz runtime built with Godot 4.7.1.

The old scenarios are more than maps and dialogue. They depend on a whole game's worth of behavior. Rewriting each one for a different engine would be a huge job, and it would be easy to lose things along the way. With Rebuilt, we're building that shared foundation once and checking differences against classic Realmz as we go.

## Play the beta

[Download the current beta for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Download the archive for your platform, extract it, and launch Realmz Rebuilt. The release includes the content needed for its bundled scenarios.

The [0.2.6 notes](docs/0.2.6.md) cover Load Saved Adventure no longer freezing while older saves update. The [0.2.5 notes](docs/0.2.5.md) cover leaving a required ally behind after battle, money that moves at classic Realmz speed with an optional Money Transfer Speed rule, the new Allies button, and Treasure with a controller. The [0.2.4 notes](docs/0.2.4.md) cover the quieter Volcanic Rockies in Trouble in the Sword Lands, frightened characters who run, battles that end when nobody fights, Castle-style missiles, and saves that update by themselves. The [0.2.3 notes](docs/0.2.3.md) cover the Trouble in the Sword Lands mountain shortcuts, steady Encounter Skills and Items panels, and HUD button titles that are now off by default. The [0.2.2 notes](docs/0.2.2.md) cover the combat fixes for helpless, charmed, frightened and confused characters and for target outlines hidden behind creatures. The [0.2.1 notes](docs/0.2.1.md) cover the fixes for problems reported in 0.2.0, including loading, money changing, the ice dragon's cave and weapon immunities, plus the optional Bard daggers rule. The [0.2.0 notes](docs/0.2.0.md) cover the new scenario runner, the new optional combat displays, save v9, and how to keep a Beta 27 fallback. Beta 27's [release notes](docs/beta-27.md) cover the death-macro and field-spell repairs that 0.2.0 retains.

You can assemble a party and head into overland maps, 2D and first-person dungeons, authored encounters, and tactical battles. Inventory, spells, treasure, services, and saving and loading are part of the game. You can use a keyboard and mouse or play entirely with a controller. If you're starting with an empty character vault, you'll also get editable copies of six Classic starter characters.

If those starters are missing or no longer compatible, open Character Files and choose Restore starter characters. Rebuilt backs up the existing vault and adds compatible starter copies while preserving your other characters.

The beta includes the thirteen scenarios that ship with classic Realmz:

Assault on Giant Mountain · Castle in the Clouds · City of Bywater · Destroy the Necronomicon · Grilochs Revenge · Half Truth · Mithril Vault · Prelude to Pestilence · Trouble in the Sword Lands · Twin Sands of Time · War in the Sword Lands · White Dragon · Wrath of the Mind Lords

We've kept the Classic look and sound while adding choices that make it easier to play today. You can choose how the display scales, set Interface Size to Auto or 100%–300%, and adjust Interface and Narrative text independently from 50%–150%. Fresh or reset preferences use Integer: world canvas with automatic whole-number zoom; loaded settings keep your saved display choice. If the window limits your requested Interface Size, Preferences shows the size the game can apply. Whole-window modes show both logical and on-screen sizes. Classic artwork uses whole-number 1x–3x scales while fonts render at their selected size. Optional pixel-art smoothing and CRT effects are also available.

## What “beta” means here

Rebuilt is playable, but we're still finding and fixing differences through real play. Including a scenario does **not** mean we've completed and verified every route through it. If something behaves differently from the original game, I want to know about it.

Please back up saves and character files you care about before testing a new beta. Rebuilt continues to use its existing local data folder, but it does not import saves or campaign projects from the earlier Realmz Remake.

0.2.6, 0.2.5, 0.2.4, 0.2.3, 0.2.2, 0.2.1, 0.2.0 and the current development source write save v9 and read v5-v9; 0.2.0 cannot open a save with the Bard daggers rule turned on, and 0.2.4 and earlier cannot open one with Money Transfer Speed above 1x. Beta 27 cannot read v9: keep an untouched v8-or-earlier save if you want to return to it. All versions use the same local data folder; extracting another copy of the game does not isolate your saves or Character Files.

## Help us improve it

The best bug reports tell us **which scenario**, **where you were** (coordinates or battle number), **what you did**, and **what happened instead of what you expected**. Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml). A save can help, but check it for private information before sharing it.

## For people who want to build it

The source is here too. You'll need Godot 4.7.1 and Git LFS to open the project with its bundled packages. Start with the [Builder's Manual](docs/builders-manual.md) if you want to explore or contribute to the code.

For custom music imports, build the bundled native helper using the [music library build instructions](docs/custom-music.md). Normal playback needs no external codec tools.

Rebuilt's original code is GPL-3.0-or-later. Realmz-derived scenarios, characters, and assets have separate CC BY-NC-SA 4.0 terms. The [third-party notices](THIRD_PARTY_NOTICES.txt) record the details and provenance.
