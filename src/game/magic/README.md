# Magic definitions

Start with `SpellCatalog` when you need to turn a stable or packed Classic spell identity into the neighboring immutable `SpellDefinition`. The active catalog is exposed as `RealmzContent.magic` and is shared by learned magic, scrolls, charged items, monsters, scenario instructions, and presentation projection.

Package assembly overlays any legal scenario-owned exact identity on the stock application catalog before `SpellCatalog` is constructed. Casting sources therefore never carry their own copy of a spell definition and never guess which package owns it.

Spell lookup is intentionally separate from spell capability and resolution. The neighboring `ClassicSpell*Rules` classes explain source-backed spell structure, while `MagicRules` coordinates the character, monster, projectile, field/scenario, target, area, roll, and effect collaborators that perform deterministic transactions using the session RNG. Their named resolution and selection records are colocated here as well. Begin with `test_package_repository.gd` for catalog construction, `test_field_spell_workflow.gd` for field magic, and `test_combat_flow.gd` for battle magic.

`FastSpellBindingState` records a character's mutable shortcut assignment, while `SpellScrollState` records a carried scroll's spell identity and remaining facts. They live here because magic defines their meaning even when a character or inventory record owns their lifetime.

Their detached counterparts—`SpellView`, `SpellScrollView`, and `FastSpellBindingView`—carry visible values and precomputed availability to presentation without exposing definitions or mutable character state.
