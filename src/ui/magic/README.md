# Spellbook UI

This folder contains the complete player-facing field spellbook. Start with `spells_screen.tscn` to edit the route sidebar and its fixed actions. Open `spells_workspace.tscn` to edit the reusable spellbook shown both on the ordinary Spells route and while an Encounter asks the player to choose a spell.

`SpellsScreenController` binds detached `SpellView` records to those scenes, preserves presentation-only selection and filtering, and emits typed intents. It does not decide whether a cast is legal or mutate the playthrough. `SpellDetailFormatter` turns already-supplied facts into display labels. `ClassicSpellSelectionChrome` and the neighboring level, heading, button, target-badge, and effect-preview scenes provide the shared selection language used here, during character creation, Level Up, and combat.

The workspace owns its stable headings, panels, empty states, level/power rails, ten Fast Spell slots, and five Scroll Case slots. Edit those named instances in `spells_workspace.tscn`, or their neighboring row scenes to change shared appearance. The ordinary route footer and the Encounter workspace each retain their authored Cast/Make Scroll dock. Only the known-spell list creates variable record instances. The route and fixed controls are retained and rebound; they are never rebuilt during movement or per frame.

Data flows in one direction:

`GameView / SpellView -> SpellsScreenController -> authored scenes -> typed intent`

When changing this feature, verify the ordinary route and Encounter picker in both Wide and Compact previews, then run the field-magic, scroll/camp, Classic UI, and Realmz Builder preview suites.
