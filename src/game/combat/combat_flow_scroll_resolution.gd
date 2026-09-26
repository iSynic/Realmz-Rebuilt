## Resolves validated scroll spells without owning scroll consumption or turn admission.
class_name CombatFlowScrollResolution
extends RefCounted

const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

var _context: CombatContext
var _selection: CombatSpellSelection
var _resolution: CombatCharacterSpellResolution


func _init(context: CombatContext, selection: CombatSpellSelection, resolution: CombatCharacterSpellResolution) -> void:
	_context = context
	_selection = selection
	_resolution = resolution


func resolve(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_id: String, target_coordinate: Vector2i, rotation: int, target_ids: Array[String], target_coordinates: Array[Vector2i], state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	if CombatFlowSummoning.is_summon_spell(spell):
		if target_coordinates.is_empty():
			return CombatFlowResult.failed(&"summon_target_required", "Choose at least one open battlefield space for the summon scroll.")
		return _context.summoning().cast_character_summon(state, content, caster, spell, power_level, rng, target_coordinates, "classic-scroll", false, false)
	if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell):
		return _context.phase().cast_character_phase(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, false, "classic-scroll", false)
	_context.actions().prepare_character_turn(state.combat, caster)
	state.combat.turns.invalidate_undo()
	if spell.target_type in [3, 4]:
		return _resolve_area(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, rotation, state_checkpoint, rng_checkpoint)
	if spell.target_type == 7:
		var party := _context.magic.resolve_character_group_spell(caster, [], [], [], spell, power_level, cast_level, rng, true, false)
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The party scroll could not be resolved.") if party == null or not party.cast else _resolution.commit(state, content, caster, spell, power_level, cast_level, party, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	if spell.target_type in [9, 10, 12]:
		return _resolve_group(state, content, caster, spell, power_level, cast_level, rng, state_checkpoint, rng_checkpoint)
	if spell.target_type == 0:
		return _resolve_repeated(state, content, caster, spell, power_level, cast_level, rng, target_ids, state_checkpoint, rng_checkpoint)
	if spell.target_type == 6:
		var ray_selections := _resolution.ray_selections(state, content, caster.id, target_id, spell)
		var ray := _context.magic.resolve_character_ray_spell(caster, ray_selections, spell, power_level, cast_level, rng, false)
		if ray == null or not ray.cast:
			return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The ray scroll could not be resolved.")
		return _resolution.commit(state, content, caster, spell, power_level, cast_level, ray, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	return _resolve_targeted(state, content, caster, spell, power_level, cast_level, rng, target_id, state_checkpoint, rng_checkpoint)


func _resolve_area(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_coordinate: Vector2i, rotation: int, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var shape := _context.spell_areas.shape_for(spell, power_level, rotation)
	var persistent_field: RefCounted = _context.fields().queue_persistent_field(state.combat, caster.id, spell, power_level, cast_level, rng, target_coordinate, rotation, shape)
	var selected_ids: Dictionary = {}
	for offset: Vector2i in _context.spell_areas.pattern(shape):
		var actor_id := state.combat.battlefield.actors.actor_at(target_coordinate + offset)
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var area_targets := _resolution.group_targets(state, content, caster, spell, selected_ids, true)
	if not bool(area_targets.get("ok", false)):
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_target_unavailable", String(area_targets.get("error", "A scroll target is unavailable.")))
	var area := _context.magic.resolve_character_group_spell(caster, area_targets.get("characters", []), area_targets.get("monsters", []), area_targets.get("definitions", []), spell, power_level, cast_level, rng, true, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()), true)
	if area == null or not area.cast:
		if area != null and not area.error_code.is_empty():
			return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, area.error_code, area.error_message)
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The area scroll could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, area, rng, target_coordinate, shape, "classic-scroll", "", false, [persistent_field])


func _resolve_group(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var group_targets := _resolution.group_targets(state, content, caster, spell)
	if not bool(group_targets.get("ok", false)):
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_target_unavailable", String(group_targets.get("error", "A scroll target is unavailable.")))
	var group := _context.magic.resolve_character_group_spell(caster, group_targets.get("characters", []), group_targets.get("monsters", []), group_targets.get("definitions", []), spell, power_level, cast_level, rng, false, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if group == null or not group.cast:
		if group != null and not group.error_code.is_empty():
			return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, group.error_code, group.error_message)
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The group scroll could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, group, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)


func _resolve_repeated(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_ids: Array[String], state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var selections: Array[SpellTargetSelection] = []
	for selected_id: String in target_ids:
		var selection := _selection.spell_target_selection(state, content, selected_id)
		if selection == null:
			return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_target_unavailable", "A repeated-scroll target became unavailable.")
		selections.append(selection)
	var repeated_fields: Array[RefCounted] = []
	var repeated := _context.magic.resolve_character_repeated_spell(caster, selections, spell, power_level, cast_level, rng, false, _context.fields().repeated_field_callback(state, spell, caster.id, target_ids, power_level, cast_level, rng, repeated_fields), content.items.definitions())
	if repeated == null or not repeated.cast:
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The repeated scroll could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, repeated, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false, repeated_fields)


func _resolve_targeted(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_id: String, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var effective_target_id := caster.id if spell.target_type == 5 else target_id
	var selection := _selection.spell_target_selection(state, content, effective_target_id)
	var field_center := state.combat.battlefield.actors.actor_position(caster.id) if spell.target_type == 5 else INVALID_COORDINATE
	var persistent_field: RefCounted = _context.fields().queue_persistent_field(state.combat, caster.id, spell, power_level, cast_level, rng, field_center, 0, 1) if spell.target_type == 5 else _context.fields().queue_single_actor_field(state, caster.id, effective_target_id, spell, power_level, cast_level, rng) if spell.target_type == 1 else null
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and persistent_field == null:
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"persistent_field_queue_failed", "The self-centered scroll field could not be queued.")
	var targeted := _context.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if targeted == null or not targeted.cast:
		if targeted != null and not targeted.error_code.is_empty():
			return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, targeted.error_code, targeted.error_message)
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The targeted scroll could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, targeted, rng, field_center, 1 if spell.target_type == 5 and persistent_field != null else 0, "classic-scroll", "", false, [persistent_field] if persistent_field != null else [])
