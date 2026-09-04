## Coordinates deterministic combat, field, and scenario spell resolvers.

class_name MagicRules
extends RefCounted

var _character_spells: CharacterSpellResolver
var _monster_spells: MonsterSpellResolver
var _projectiles: SpellProjectileResolver
var _field_scenario_spells: FieldScenarioSpellResolver


func _init(character_rules: CharacterRules = null, realmz_arithmetic: RealmzArithmetic = null, monster_rules: MonsterRules = null) -> void:
	_character_spells = CharacterSpellResolver.new(character_rules, realmz_arithmetic, monster_rules)
	_monster_spells = MonsterSpellResolver.new(character_rules, realmz_arithmetic, monster_rules)
	_projectiles = SpellProjectileResolver.new(character_rules, realmz_arithmetic, monster_rules)
	_field_scenario_spells = FieldScenarioSpellResolver.new(character_rules, realmz_arithmetic, monster_rules)


func resolve_character_targeted_spell(caster: CharacterState, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
	return _character_spells.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, spend_spell_points, polymorph_context)


func roll_persistent_field_duration(spell: SpellDefinition, power_level: int, rng: RealmzRng, tag: StringName) -> int:
	return _character_spells.roll_persistent_field_duration(spell, power_level, rng, tag)


func resolve_character_group_spell(caster: CharacterState, character_targets: Array[CharacterState], monster_targets: Array[MonsterState], monster_definitions: Array[MonsterDefinition], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_empty: bool = false, spend_spell_points: bool = true, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
	return _character_spells.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng, allow_empty, spend_spell_points, polymorph_context)


func resolve_character_area_projectile_item(caster: CharacterState, caste: CasteDefinition, projectile_item: ItemDefinition, character_targets: Array[CharacterState], monster_targets: Array[MonsterState], monster_definitions: Array[MonsterDefinition], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> GroupSpellResolution:
	return _character_spells.resolve_character_area_projectile_item(caster, caste, projectile_item, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng)


func resolve_character_repeated_spell(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true, before_selection: Callable = Callable(), item_definitions: Array[ItemDefinition] = []) -> RepeatedSpellResolution:
	return _character_spells.resolve_character_repeated_spell(caster, selections, spell, power_level, cast_level, rng, spend_spell_points, before_selection, item_definitions)


func resolve_character_ray_spell(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true) -> RepeatedSpellResolution:
	return _character_spells.resolve_character_ray_spell(caster, selections, spell, power_level, cast_level, rng, spend_spell_points)


func resolve_character_projectile(caster: CharacterState, caste: CasteDefinition, projectile_item: ItemDefinition, target: MonsterState, spell: SpellDefinition, power_level: int, rng: RealmzRng) -> ProjectileResolution:
	return _projectiles.resolve_character_projectile(caster, caste, projectile_item, target, spell, power_level, rng)


func resolve_monster_projectile(caster: MonsterState, projectile_item: ItemDefinition, target: CharacterState, spell: SpellDefinition, power_level: int, rng: RealmzRng) -> ProjectileResolution:
	return _projectiles.resolve_monster_projectile(caster, projectile_item, target, spell, power_level, rng)


func character_resists(caster_level: int, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, extra_to_hit_bonus: int = 0) -> bool:
	return _projectiles.character_resists(caster_level, target, spell, power_level, cast_level, rng, extra_to_hit_bonus)


func resolve_monster_targeted_spell(caster: MonsterState, caster_definition: MonsterDefinition, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
	return _monster_spells.resolve_monster_targeted_spell(caster, caster_definition, selection, spell, power_level, cast_level, rng, polymorph_context)


func resolve_monster_group_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_empty: bool = false, spend_spell_points: bool = true, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
	return _monster_spells.resolve_monster_group_spell(caster, caster_definition, selections, spell, power_level, cast_level, rng, allow_empty, spend_spell_points, polymorph_context)


func resolve_monster_repeated_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, before_selection: Callable = Callable()) -> RepeatedSpellResolution:
	return _monster_spells.resolve_monster_repeated_spell(caster, caster_definition, selections, spell, power_level, cast_level, rng, before_selection)


func resolve_monster_ray_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> RepeatedSpellResolution:
	return _monster_spells.resolve_monster_ray_spell(caster, caster_definition, selections, spell, power_level, cast_level, rng)


static func condition_cure_index(spell: SpellDefinition) -> int:
	return SpellResolutionSupport.condition_cure_index(spell)


static func is_condition_cure_spell(spell: SpellDefinition) -> bool:
	return SpellResolutionSupport.is_condition_cure_spell(spell)


func resolve_field_spell(caster: CharacterState, targets: Array[CharacterState], spell: SpellDefinition, power_level: int, rng: RealmzRng, castes: Array[CasteDefinition] = [], races: Array[RaceDefinition] = [], spend_spell_points: bool = true, allow_empty: bool = false, item_definitions: Array[ItemDefinition] = [], ally_targets: Array[MonsterState] = [], ally_definitions: Array[MonsterDefinition] = []) -> GroupSpellResolution:
	return _field_scenario_spells.resolve_field_spell(caster, targets, spell, power_level, rng, castes, races, spend_spell_points, allow_empty, item_definitions, ally_targets, ally_definitions)


func resolve_scenario_spell(target: CharacterState, spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, caste: CasteDefinition = null, race: RaceDefinition = null) -> SpellResolution:
	return _field_scenario_spells.resolve_scenario_spell(target, spell, power_level, extra_save_adjust, force_affect, rng, caste, race)


func resolve_scenario_group_spell(targets: Array[CharacterState], spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, castes: Array[CasteDefinition] = [], races: Array[RaceDefinition] = []) -> GroupSpellResolution:
	return _field_scenario_spells.resolve_scenario_group_spell(targets, spell, power_level, extra_save_adjust, force_affect, rng, castes, races)
