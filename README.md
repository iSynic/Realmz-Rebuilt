# Realmz Rebuilt

Rebuilt is a new way to play the Classic scenarios on modern computers while keeping their maps, encounters, rules, art, and quirks recognizable. A greenfield, cross-platform Realmz runtime built with Godot 4.7.1.

The old scenarios are more than maps and dialogue. They depend on a whole game's worth of behavior. Rewriting each one for a different engine would be a huge job, and it would be easy to lose things along the way. With Rebuilt, we're building that shared foundation once and checking differences against the Realmz Castle codebase as we go.

## Play the beta

[Download the current beta for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases). Download the archive for your platform, extract it, and launch Realmz Rebuilt. The release includes the content needed for its bundled scenarios.

You can assemble a party and head into overland maps, 2D and first-person dungeons, authored encounters, and tactical battles. Inventory, spells, treasure, services, and saving and loading are part of the game. You can use a keyboard and mouse or play entirely with a controller. If you're starting with an empty character vault, you'll also get editable copies of six Classic starter characters.

The beta includes the thirteen scenarios that ship with the Realmz Castle codebase:

Assault on Giant Mountain · Castle in the Clouds · City of Bywater · Destroy the Necronomicon · Grilochs Revenge · Half Truth · Mithril Vault · Prelude to Pestilence · Trouble in the Sword Lands · Twin Sands of Time · War in the Sword Lands · White Dragon · Wrath of the Mind Lords

We've kept the Classic look and sound while adding choices that make it easier to play today. You can choose how the display scales, set Interface Size to Auto or 100%–300%, and add a separate Text Size adjustment from 80%–150%. Fresh or reset preferences use Integer: world canvas; loaded settings keep your saved display choice. If the window limits your requested Interface Size, Preferences shows the size the game can apply. Whole-window modes show both logical and on-screen sizes. Classic artwork uses whole-number 1x–3x scales while fonts render at their selected size. Optional pixel-art smoothing and CRT effects are also available.

## What “beta” means here

Rebuilt is playable, but we're still finding and fixing differences through real play. Including a scenario does **not** mean we've completed and verified every route through it. If something behaves differently from the original game, I want to know about it.

Please back up saves and character files you care about before testing a new beta. Rebuilt continues to use its existing local data folder, but it does not import saves or campaign projects from the earlier Realmz Remake.

## Help us improve it

The best bug reports tell us **which scenario**, **where you were** (coordinates or battle number), **what you did**, and **what happened instead of what you expected**. Please use the [beta bug report form](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml). A save can help, but check it for private information before sharing it.

## For people who want to build it

The source is here too. You'll need Godot 4.7.1 and Git LFS to open the project with its bundled packages. Start with the [Builder's Manual](docs/builders-manual.md) if you want to explore or contribute to the code.

For custom music imports, build the bundled native helper using the [music library build instructions](docs/custom-music.md). Normal playback needs no external codec tools.

Rebuilt's original code is GPL-3.0-or-later. Realmz-derived scenarios, characters, and assets have separate CC BY-NC-SA 4.0 terms. The [third-party notices](THIRD_PARTY_NOTICES.txt) record the details and provenance.
