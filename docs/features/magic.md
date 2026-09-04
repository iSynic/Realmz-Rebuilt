# Magic

`SpellDefinition` is authored content and `MagicRules` is the stable spell-resolution entry point used by gameplay. Follow character casts into `CharacterSpellResolver`, monster casts into `MonsterSpellResolver`, missile and thrown spell attacks into `SpellProjectileResolver`, and field or scenario effects into `FieldScenarioSpellResolver`. `SpellResolutionSupport` holds only the targeting, resistance, effect, and scaling mechanics shared by those resolvers. Combat orchestration still enters through `CombatFlow`.

Known spells, scroll slots, charges, selected power, targets, and continuations remain typed and saveable. Every casting surface receives detached `SpellView` records with current-context availability.

Outside combat, `FieldMagicWorkflow` owns Fast Spell binding, scroll scribing and use, and learned spell casting. `FieldItemWorkflow` owns magic carried-item use. Both share `FieldMagicTargetRequestBuilder` for the exact saveable character-selection contract, `FieldMagicResolver` for stable party/allied target order and committed effects, and the top-level `MagicTransitionResult` returned to session coordination.

Do not classify spells by their names or duplicate lists of special IDs. `ClassicSpellIdentityCatalog` owns packed application identity, `ClassicSpellClassificationRules` owns mechanical family and behavior signatures, and `ClassicSpellDispositionRules` decides which casting sources can execute a record. `ClassicSpellSourceRules`, `ClassicSpellConditionRules`, and `ClassicSpellSpecialEffectRules` recognize the exact source-backed record structures used by those decisions. Field behavior belongs to `test_field_spell_workflow.gd`; scroll and camp behavior belongs to `test_scroll_camp_workflow.gd`; combat timing is sampled by `combat_performance_probe.gd`.

## Where to start

- Edit the ordinary and Encounter spellbook layout in `src/ui/screens/spells_workspace.tscn`; `spells_screen.tscn` embeds it for the route.
- Edit the reusable action, Fast Spell, and scroll records in their neighboring `spell_action_dock.tscn`, `fast_spell_row.tscn`, and `spell_scroll_slot_row.tscn` scenes.
- Follow screen binding and presentation-local selection through `SpellsScreenController`. It formats detached facts, reuses the authored workspace, and instantiates only the exported variable record scenes.
- Follow a submitted `MagicIntents` command through `PlayerIntent`, `GameSession`, and the field or combat workflow. Rules, target legality, costs, effects, RNG, and saved state never live in the UI.

The spellbook is retained for a route presentation; it is not rebuilt per movement step or frame. When changing its layout, exercise both Wide and Compact profiles plus Encounter selection, Fast Spell assignment, Scroll Case confirmation, field casting, and combat magic.
