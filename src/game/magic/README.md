# Magic definitions

Start with `SpellCatalog` when you need to turn a stable or packed Classic spell identity into the neighboring immutable `SpellDefinition`. The active catalog is exposed as `RealmzContent.magic` and is shared by learned magic, scrolls, charged items, monsters, scenario instructions, and presentation projection.

Package assembly overlays any legal scenario-owned exact identity on the stock application catalog before `SpellCatalog` is constructed. Casting sources therefore never carry their own copy of a spell definition and never guess which package owns it.

Spell lookup is intentionally separate from spell capability and resolution. The `ClassicSpell*Rules` classes explain source-backed spell structure, while `MagicRules` and its field/combat collaborators perform deterministic transactions using the session RNG. Begin with `test_package_repository.gd` for catalog construction, `test_field_spell_workflow.gd` for field magic, and `test_combat_flow.gd` for battle magic.
