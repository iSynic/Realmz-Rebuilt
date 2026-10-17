# Realmz Rebuilt Beta 21

Beta 21 adds an optional modular HUD, cleaner Settings pages, a refined Theldrow font, and a substantial combat-feedback update. You can slow down scrolling combat text without slowing the battle, condense large group effects, and keep the familiar command artwork in either HUD layout.

[Download Realmz Rebuilt for Windows, Linux, or macOS](https://github.com/iSynic/Realmz-Rebuilt/releases).

## Combat feedback

- **Sharper, more readable results.** Damage, healing, saves, misses, and status results appear near the affected combatant and scroll upward with smooth motion and fading. Text uses a stout outline and a translucent background. Enlarging the world now renders the lettering at the resolved viewport density instead of enlarging a small glyph bitmap.
- **Separate text timing.** Settings > Pacing has independent Combat & animation speed and Scrolling combat text speed controls. Lowering text speed keeps results readable while actions continue at the chosen battle speed. Combat text background opacity is separately adjustable from 0% to 100%.
- **Saved damage stays visible.** A successful save that still allows damage shows both the save and the actual damage taken. The combat account also retains the committed amount. A save no longer hides that information behind a lone “Saved” label.
- **Clearer status attacks.** Announced physical charm, paralysis, and related mental-status attacks use their source-backed purple effect and sound. These cues report the resolved status without applying damage a second time. Successful spell casts retain their own authored effect; a resisted spell does not borrow the physical attack's purple circle.
- **Complete multi-target effects.** Successful recipients receive the complete eight-frame effect, including later recipients of buffs such as Magic Aura. Individual playback uses shorter buff-result holds. Condense Multi-Target Playback shows eligible recipients together while preserving their individual results in the combat account. Scrolling text stays near each recipient and may overlap naturally.
- **Consistent elemental impact timing.** Fire, ice, and lightning portions of weapons such as The Four Winds follow the same base visual pacing as the physical hit. Their complete sound clips play asynchronously instead of extending every visual hold. Combat speed and Auto apply consistently to those impact holds.
- **Charm handoff.** A character charmed by a Guard reaction during movement hands control to the appropriate automation path instead of leaving an unusable manual turn. The same activation and remaining allowances are retained.
- **Fewer redundant Auto buffs.** Party Auto avoids choosing condition buffs whose recipients would gain no mechanical benefit from the current cast. This changes action selection, not spell costs or effects.
- **Settings during combat.** Opening Settings from combat keeps its controls above the battle's retained presentation instead of leaving an unresponsive preferences page.

These changes address the reports about [long buff effects (#9)](https://github.com/iSynic/Realmz-Rebuilt/issues/9), [missing saved-damage amounts (#10)](https://github.com/iSynic/Realmz-Rebuilt/issues/10), [damage-display readability (#11)](https://github.com/iSynic/Realmz-Rebuilt/issues/11), and [missing charm feedback (#12)](https://github.com/iSynic/Realmz-Rebuilt/issues/12).

## Optional modular HUD

The fixed HUD remains the default. To try the alternative, open Settings > Interface > HUD panels and select Modular.

- Arrange the roster, narration, command panels, and effects dock independently. Resize the narration and roster areas and choose Auto, Horizontal, or Vertical orientation for the command and effects strips.
- Compact commands fit the icons with minimal padding. The original command images, Search animation, and Torch frames are used; the experimental replacement icons are not selected in game. Torch occupies a fixed-size slot so it cannot stretch a short command panel.
- Set panel backgrounds independently without fading their text or icons. Modular panels use flat translucent surfaces and reserve their space for game content rather than title bars.
- Choose Always visible or Auto-hide for all panels, then adjust individual panels if desired. Hidden panels retain subtle wordless reveal tabs and pointer/controller access.
- Meaningful health, spell-point, and condition changes can briefly reveal the roster. New narration can reveal its panel long enough to read. Routine coordinate, clock, and fatigue refreshes do not repeatedly open narration; command availability and Torch changes do not automatically open their panels.
- Arrange stages a layout in the Settings draft. Apply commits it; Cancel preserves the previous settings. Reset layout restores default geometry and orientation.

## Settings, typography, and shortcuts

- Pause and Settings share the main menu's typography, gold selection treatment, and blurred adventure backdrop. Settings keeps the larger presentation when moving into its preference pages.
- Preferences use compact task groups, bounded fields, and nearby switches. Redundant subtab headings are removed, and hovering a tab no longer shifts its lettering sideways.
- Controls reference pages use editable Action/Input tables for general, Classic exploration, and Classic combat shortcuts instead of dense paragraphs of repeated instructions.
- Theldrow's revised letter outlines improve lowercase body alignment, stroke consistency, and capital weight while preserving the font's familiar character. Interface and Narrative font choices and sizes remain independent.
- **F5** performs Quicksave and **F7** performs Quickload using the adventure's active A–J save slot, subject to the normal save/load availability rules.
- Holding field Heal requests its sound once per activation rather than queuing repeated copies that continue after release.

## Updating and known limitations

The bundled scenario packages, save format, and Character Files format are unchanged from the refreshed Beta 20 release. This update does not require a new save conversion or scenario reimport. Back up saves and characters you care about before testing; keep the supplied importer and music-importer folders with the application.

An intermittent combat spellbook-input problem remains unresolved: Power Level, Choose Targets, and Abort have sometimes stopped responding while Back to battle still works. Returning to battle and reopening Spells may restore them. The problem later cleared during testing, but it is not claimed fixed in this release. If it recurs, include the build, scenario, caster, spell, and the actions immediately before it happened in a bug report.

Combat changes were checked against the Realmz Castle codebase and exercised in isolated Rebuilt fixtures, including native Windows Mobile/Vulkan and OpenGL rendering. That is not a claim of complete campaign certification or an identical controlled Castle runtime comparison. The beta still needs ordinary play across its scenarios.

Fresh Windows x86_64, Linux x86_64, and universal macOS archives are supplied with `SHA256SUMS` for download verification.
