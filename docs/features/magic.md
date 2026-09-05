# Magic

`SpellDefinition` is authored content, `RealmzContent.magic` exposes its effective `SpellCatalog`, and `MagicRules` is the stable spell-resolution entry point used by gameplay. Package assembly applies scenario exact-ID overlays before the catalog is indexed, so every casting source resolves the same immutable definition. Follow character casts into `CharacterSpellResolver`, monster casts into `MonsterSpellResolver`, missile and thrown spell attacks into `SpellProjectileResolver`, and field or scenario effects into `FieldScenarioSpellResolver`. `SpellResolutionSupport` holds only the targeting, resistance, effect, and scaling mechanics shared by those resolvers. Combat orchestration still enters through `CombatFlow`.

Known spells, scroll slots, charges, selected power, targets, and continuations remain typed and saveable. Every casting surface receives detached `SpellView` records with current-context availability. Its constructor either populates immutable authored facts or copies a reusable revision-local view, making that allocation policy explicit without changing the detached contract.

Outside combat, `src/playthrough/magic` gathers the complete transaction: `FieldMagicWorkflow` owns Fast Spell binding, scroll scribing and use, and learned spell casting. `FieldItemWorkflow` in the neighboring Inventory feature owns magic carried-item use. Both share `FieldMagicTargetRequestBuilder` for the exact saveable character-selection contract, `FieldMagicResolver` for stable party/allied target order and committed effects, and `MagicTransitionResult` for the result returned to session coordination.

`MagicContinuations` creates field-spell targets, scroll targets, and invalid-scroll discard confirmations with one typed `TargetingContinuationBody`. `SessionRestoreValidator` revalidates those source families separately before accepting a saved interaction. Those live values become dictionaries only through `SessionContinuationCodec` at the save boundary.

`FieldScenarioSpellResolver` reads in the same order as the underlying transaction: save and protection, condition mutation, spell special, aging, then final health mutation. The small `NoncombatEffectRoll` carries the adjusted damage and save result between those phases without entering state, events, or a save record.

Do not classify spells by their names or duplicate lists of special IDs. `ClassicSpellIdentityCatalog` owns packed application identity, `ClassicSpellClassificationRules` owns mechanical family and behavior signatures, and `ClassicSpellDispositionRules` decides which casting sources can execute a record. `ClassicSpellSourceRules`, `ClassicSpellConditionRules`, and `ClassicSpellSpecialEffectRules` recognize the exact source-backed record structures used by those decisions. Field behavior belongs to `test_field_spell_workflow.gd`; scroll and camp behavior belongs to `test_scroll_camp_workflow.gd`; combat timing is sampled by `combat_performance_probe.gd`.

## Where to start

- Open `src/game/magic` for immutable spell lookup and `src/ui/magic` for the complete player-facing spellbook feature. Edit ordinary and Encounter layout in `spells_workspace.tscn`; `spells_screen.tscn` embeds it for the route.
- Edit the reusable action, Fast Spell, and scroll records in their neighboring `spell_action_dock.tscn`, `fast_spell_row.tscn`, and `spell_scroll_slot_row.tscn` scenes.
- Follow screen binding and presentation-local selection through `SpellsScreenController`; `SpellDetailFormatter` owns the display-only target, power, resistance, save, and scaled-range text. The controller reuses the authored workspace and instantiates only its exported variable record scenes.
- Follow a submitted `MagicIntents` command through `PlayerIntent`, `GameSession`, and `src/playthrough/magic/field_magic_workflow.gd` or the combat workflow. Rules, target legality, costs, effects, RNG, and saved state never live in the UI.

The spellbook is retained for a route presentation; it is not rebuilt per movement step or frame. When changing its layout, exercise both Wide and Compact profiles plus Encounter selection, Fast Spell assignment, Scroll Case confirmation, field casting, and combat magic.
