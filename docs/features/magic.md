# Magic

`SpellDefinition` is authored content, `MagicRules` owns field effects and shared calculations, and combat magic enters through `CombatFlow`. Known spells, scroll slots, charges, selected power, targets, and continuations remain typed and saveable. Every casting surface receives detached `SpellView` records with current-context availability.

Do not classify spells by their names or duplicate lists of special IDs. The application capability catalog and the owning rules decide what a spell can do. Field behavior belongs to `test_field_spell_workflow.gd`; scroll and camp behavior belongs to `test_scroll_camp_workflow.gd`; combat timing is sampled by `combat_performance_probe.gd`.
