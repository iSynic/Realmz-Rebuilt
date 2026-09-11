## Resolves validated character spell, scroll, and charged-item combat actions.
class_name CombatFlowMagic
extends RefCounted


const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2
const MONSTER_ATTACK_FALLBACK := 3
const REACTION_COMPLETED := 0
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const MAX_MONSTERS: int = 100
const MAX_AUTO_OPERATIONS: int = 256
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)
const CHARACTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 10123, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": false},
]
const MONSTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": true},
]

var _context: CombatContext
var _selection: CombatSpellSelection
var _resolution: CombatCharacterSpellResolution


func _init(context: CombatContext) -> void:
	_context = context
	_selection = CombatSpellSelection.new(context)
	_resolution = CombatCharacterSpellResolution.new(context, _selection)


func selection() -> CombatSpellSelection:
	return _selection


func cast_macro_spell(state: GameState, content: RealmzContent, source_id: String, spell: SpellDefinition, power: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng) -> CombatFlowResult:
	return CombatMacroSpells.new(_context).cast(state, content, source_id, spell, power, extra_save_adjust, force_affect, rng)

func probe_character_item_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_item_turn", "Item use requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_item_turn", "Only the active character may use an item in combat.")
	if not combat.spell_runtime.pending_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	var instance := inventory_instance(caster, instance_id)
	var item: ItemDefinition = null if instance == null else content.items.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else content.magic.spell_by_classic_id(item.special_2)
	var use_probe := _context.inventory.classic_spell_item_probe(caster, instance, item, spell, content.characters.race_by_id(caster.race_id) if caster != null else null, content.characters.caste_by_id(caster.caste_id) if caster != null else null, true)
	if not use_probe.allowed:
		return CombatSpellCastProbe.blocked(item_use_reason_code(instance, item, spell), use_probe.reason)
	if ClassicSpellDispositionRules.combat_item_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_item_effect", ClassicSpellDispositionRules.unsupported_reason(spell, &"combat-item"))
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and not combat.spell_runtime.can_queue_persistent_field():
		return CombatSpellCastProbe.blocked(&"persistent_field_queue_limit", "Castle's persistent battlefield-field queue is full.")
	var staged_instance_id := combat.turns.staged_random_item_instance_id()
	if not staged_instance_id.is_empty() and staged_instance_id != instance.id:
		return CombatSpellCastProbe.blocked(&"random_item_target_pending", "Finish targeting the random-power item already staged for this activation.")
	var authored_power := absi(item.special_1)
	var power_level := combat.turns.staged_random_item_power(caster_id, instance.id) if authored_power == 8 else authored_power
	var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
	if authored_power == 8 and power_level == 0:
		if not target_id.is_empty() or not target_ids.is_empty() or not target_coordinates.is_empty() or target_coordinate != INVALID_COORDINATE or rotation != 0:
			return CombatSpellCastProbe.blocked(&"random_item_power_not_staged", "Roll this item's power before choosing its combat target.")
		return CombatSpellCastProbe.permitted()
	if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) or ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell): return CombatSpellCastProbe.permitted() if target_coordinate == INVALID_COORDINATE else _context.phase().probe_destination(state, content, caster_id, spell, power_level, target_coordinate)
	if spell.target_type == 0:
		return _probe_repeated_item_spell(state, content, caster, spell, power_level, target_ids, target_coordinates, summon_spell)
	if spell.target_type in [3, 4]:
		return _probe_item_area_spell(state, content, caster, spell, power_level, target_coordinate, rotation)
	if spell.target_type in [9, 10, 12]:
		return _probe_item_group_spell(state, content, caster, spell)
	var effective_target_id := caster_id if spell.target_type in [5, 7] else target_id
	if _selection.spell_target_selection(state, content, effective_target_id) == null:
		return CombatSpellCastProbe.blocked(&"invalid_item_target", "The selected combatant is unavailable.")
	if not _selection.spell_actor_target_is_valid(state, content, caster_id, effective_target_id, spell, power_level):
		return CombatSpellCastProbe.blocked(&"item_target_unavailable", "The target is outside the item's Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func _probe_repeated_item_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, target_ids: Array[String], target_coordinates: Array[Vector2i], summon_spell: bool) -> CombatSpellCastProbe:
	if summon_spell:
		return _context.summoning().probe_choice(state, content, caster.id, spell, power_level) if target_coordinates.is_empty() else _context.summoning().probe_coordinates(state, content, caster.id, spell, power_level, target_coordinates)
	if spell.size != 0:
		return CombatSpellCastProbe.blocked(&"repeated_open_space_spell_unresolved", "Classic target type 0 with nonzero size selects open-space footprints for summoning or special behavior, not ordinary actors.")
	if target_ids.size() > power_level:
		return CombatSpellCastProbe.blocked(&"too_many_item_targets", "A repeated item spell may select at most one distinct actor per power level.")
	var seen: Dictionary = {}
	for selected_id: String in target_ids:
		if selected_id.is_empty() or seen.has(selected_id):
			return CombatSpellCastProbe.blocked(&"invalid_repeated_item_targets", "Repeated item targets must be nonempty and distinct.")
		seen[selected_id] = true
		if _selection.spell_target_selection(state, content, selected_id) == null:
			return CombatSpellCastProbe.blocked(&"invalid_item_target", "A selected repeated-item actor is unavailable.")
		if not _selection.spell_actor_target_is_valid(state, content, caster.id, selected_id, spell, power_level):
			return CombatSpellCastProbe.blocked(&"item_target_unavailable", "A selected repeated-item actor is outside the Classic spell range or line of sight.")
	if target_ids.is_empty() and _selection.character_actor_spell_candidates(state, content, caster, spell, power_level).is_empty():
		return CombatSpellCastProbe.blocked(&"item_target_unavailable", "No actor is available within this repeated item's Classic range and line of sight.")
	return CombatSpellCastProbe.permitted()


func _probe_item_area_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, target_coordinate: Vector2i, rotation: int) -> CombatSpellCastProbe:
	if _selection.invalid_area_rotation(spell, rotation):
		return CombatSpellCastProbe.blocked(&"invalid_area_rotation", "This Classic area spell does not support the selected orientation.")
	var shape := _context.spell_areas.shape_for(spell, power_level, rotation)
	if _context.spell_areas.pattern(shape).is_empty():
		return CombatSpellCastProbe.blocked(&"invalid_item_area_shape", "The item references an unavailable Classic Data AD area mask.")
	if target_coordinate == INVALID_COORDINATE:
		return CombatSpellCastProbe.permitted()
	if not _context.spell_areas.pattern_fits(target_coordinate, shape):
		return CombatSpellCastProbe.blocked(&"item_area_outside_battlefield", "The complete Classic area mask must remain inside the validated battlefield.")
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	if terrain_set == null or not _context.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster.id, target_coordinate, maximum_range, spell.range_min + spell.range_max > 0):
		return CombatSpellCastProbe.blocked(&"item_target_unavailable", "The area center is outside the item's Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func _probe_item_group_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition) -> CombatSpellCastProbe:
	var group_target_count := 0
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id) and _selection.group_target_matches(spell.target_type, character.traitor, caster.traitor):
			group_target_count += 1
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.actors.has_actor(monster.id) or not _selection.group_target_matches(spell.target_type, monster.traitor, caster.traitor):
			continue
		if content.combat.monster_by_id(monster.definition_id) == null:
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "An item spell target has no immutable monster definition.")
		group_target_count += 1
	if group_target_count == 0:
		return CombatSpellCastProbe.blocked(&"invalid_item_target", "The item spell has no available group target.")
	return CombatSpellCastProbe.permitted()


func use_spell_item(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	var probe := probe_character_item_spell(state, content, caster_id, target_id, instance_id, target_coordinate, rotation, target_ids, target_coordinates)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var caster := state.party.character_by_id(caster_id)
	var instance := inventory_instance(caster, instance_id)
	var item := content.items.item_by_id(instance.definition_id)
	var spell := content.magic.spell_by_classic_id(item.special_2)
	var authored_power := absi(item.special_1)
	var power_level := state.combat.turns.staged_random_item_power(caster_id, instance.id) if authored_power == 8 else authored_power
	var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
	if authored_power == 8 and power_level == 0:
		var stage_state_checkpoint := state.to_data()
		var stage_rng_checkpoint := rng.checkpoint()
		_context.actions().prepare_character_turn(state.combat, caster)
		power_level = rng.draw(7, StringName("combat.item.power.%s" % instance.id))
		if not state.combat.turns.stage_random_item_power(caster.id, instance.id, power_level):
			return CombatFlowSpellRollback.item(state, rng, stage_state_checkpoint, stage_rng_checkpoint, &"item_power_stage_failed", "The random item power could not be staged for targeting.")
		return CombatFlowResult.succeeded([DomainEvent.new(&"combat_item_power_staged", {"actorId": caster.id, "instanceId": instance.id, "itemId": item.id, "spellId": spell.id, "power": power_level, "source": "classic-item"})])
	if spell.target_type in [3, 4] and target_coordinate == INVALID_COORDINATE:
		return CombatFlowResult.failed(&"item_area_target_required", "Choose a battlefield center for this area item.")
	if summon_spell and target_coordinates.is_empty():
		return CombatFlowResult.failed(&"summon_target_required", "Choose at least one open battlefield space for this summon item.")
	if not summon_spell and spell.target_type == 0 and target_ids.is_empty():
		return CombatFlowResult.failed(&"item_target_required", "Choose at least one actor for this repeated item spell.")
	if (ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) or ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell)) and target_coordinate == INVALID_COORDINATE:
		return CombatFlowResult.failed(&"item_area_target_required", "Choose a battlefield destination for Phase.")
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	if not _context.inventory.use_charge(caster, instance.id, item):
		return CombatFlowResult.failed(&"item_charge_commit_failed", "The validated item charge could not be committed.")
	var cast_level := spell.classic_tier()
	if not ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) and not ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell) and not summon_spell:
		_context.actions().prepare_character_turn(state.combat, caster)
		state.combat.turns.invalidate_undo()
	var result := _resolve_spell_item(state, content, caster, instance, item, spell, power_level, cast_level, rng, target_id, target_coordinate, rotation, target_ids, target_coordinates, summon_spell, state_checkpoint, rng_checkpoint)
	if not result.ok:
		return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, result.error_code, result.error_message)
	state.combat.turns.clear_staged_random_item_power()
	var events: Array[DomainEvent] = [item_used_event(caster_id, instance_id, item, spell, power_level, caster)]
	var native_sound_id := item.sound_id + 600
	if item.sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": "classic-item"}))
	events.append_array(result.events)
	result.events = events
	return result


func _resolve_spell_item(state: GameState, content: RealmzContent, caster: CharacterState, instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_id: String, target_coordinate: Vector2i, rotation: int, target_ids: Array[String], target_coordinates: Array[Vector2i], summon_spell: bool, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var result: CombatFlowResult
	if summon_spell:
		result = _context.summoning().cast_character_summon(state, content, caster, spell, power_level, rng, target_coordinates, "classic-item", false, false)
	elif ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) or ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell):
		result = _context.phase().cast_character_phase(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, false, "classic-item", false)
	elif spell.target_type in [3, 4]:
		result = _resolve_area_spell_item(state, content, caster, instance, item, spell, power_level, cast_level, rng, target_coordinate, rotation, state_checkpoint, rng_checkpoint)
	elif spell.target_type == 0:
		result = _resolve_repeated_spell_item(state, content, caster, instance, spell, power_level, cast_level, rng, target_ids, state_checkpoint, rng_checkpoint)
	elif spell.target_type == 6:
		var ray_selections := _resolution.ray_selections(state, content, caster.id, target_id, spell)
		var ray := _context.magic.resolve_character_ray_spell(caster, ray_selections, spell, power_level, cast_level, rng, false)
		if ray == null or not ray.cast:
			return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_spell_failed", "The item ray spell could not be resolved.")
		result = _resolution.commit(state, content, caster, spell, power_level, cast_level, ray, rng, INVALID_COORDINATE, 0, "classic-item", instance.id, false)
	elif spell.target_type == 7:
		var party := _context.magic.resolve_character_group_spell(caster, [], [], [], spell, power_level, cast_level, rng, true, false)
		result = CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_spell_failed", "The party item spell could not be resolved.") if party == null or not party.cast else _resolution.commit(state, content, caster, spell, power_level, cast_level, party, rng, INVALID_COORDINATE, 0, "classic-item", instance.id, false)
	elif spell.target_type in [9, 10, 12]:
		result = _resolve_group_spell_item(state, content, caster, instance, spell, power_level, cast_level, rng, state_checkpoint, rng_checkpoint)
	else:
		result = _resolve_targeted_spell_item(state, content, caster, instance, spell, power_level, cast_level, rng, target_id, state_checkpoint, rng_checkpoint)
	return result


func _resolve_area_spell_item(state: GameState, content: RealmzContent, caster: CharacterState, instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_coordinate: Vector2i, rotation: int, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var shape := _context.spell_areas.shape_for(spell, power_level, rotation)
	var persistent_field: RefCounted = _context.fields().queue_persistent_field(state.combat, caster.id, spell, power_level, cast_level, rng, target_coordinate, rotation, shape)
	var selected_ids: Dictionary = {}
	for offset: Vector2i in _context.spell_areas.pattern(shape):
		var actor_id := state.combat.battlefield.actors.actor_at(target_coordinate + offset)
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var area_targets := _resolution.group_targets(state, content, caster, spell, selected_ids, true)
	if not bool(area_targets.get("ok", false)):
		return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_target_unavailable", String(area_targets.get("error", "An item target is unavailable.")))
	var area := _context.magic.resolve_character_area_projectile_item(caster, content.characters.caste_by_id(caster.caste_id), item, area_targets.get("characters", []), area_targets.get("monsters", []), area_targets.get("definitions", []), spell, power_level, cast_level, rng) if ClassicSpellSourceRules.is_application_area_projectile_item_profile(spell) else _context.magic.resolve_character_group_spell(caster, area_targets.get("characters", []), area_targets.get("monsters", []), area_targets.get("definitions", []), spell, power_level, cast_level, rng, true, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if area == null or not area.cast:
		return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_spell_failed", "The area item spell could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, area, rng, target_coordinate, shape, "classic-item", instance.id, false, [persistent_field])


func _resolve_repeated_spell_item(state: GameState, content: RealmzContent, caster: CharacterState, instance: ItemInstance, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_ids: Array[String], state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var selections: Array[SpellTargetSelection] = []
	for selected_id: String in target_ids:
		var repeated_selection := _selection.spell_target_selection(state, content, selected_id)
		if repeated_selection == null:
			return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_target_unavailable", "A repeated-item target became unavailable.")
		selections.append(repeated_selection)
	var repeated_fields: Array[RefCounted] = []
	var repeated := _context.magic.resolve_character_repeated_spell(caster, selections, spell, power_level, cast_level, rng, false, _context.fields().repeated_field_callback(state, spell, caster.id, target_ids, power_level, cast_level, rng, repeated_fields), content.items.definitions())
	if repeated == null or not repeated.cast:
		return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_spell_failed", "The repeated item spell could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, repeated, rng, INVALID_COORDINATE, 0, "classic-item", instance.id, false, repeated_fields)


func _resolve_group_spell_item(state: GameState, content: RealmzContent, caster: CharacterState, instance: ItemInstance, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var character_targets: Array[CharacterState] = []
	var monster_targets: Array[MonsterState] = []
	var monster_definitions: Array[MonsterDefinition] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id) and _selection.group_target_matches(spell.target_type, character.traitor, caster.traitor):
			character_targets.append(character)
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.actors.has_actor(monster.id) or not _selection.group_target_matches(spell.target_type, monster.traitor, caster.traitor):
			continue
		var definition := content.combat.monster_by_id(monster.definition_id)
		if definition == null:
			return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"spell_target_unavailable", "An item spell target has no immutable monster definition.")
		monster_targets.append(monster)
		monster_definitions.append(definition)
	var group := _context.magic.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng, false, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if group == null or not group.cast:
		return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_spell_failed", "The item spell could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, group, rng, INVALID_COORDINATE, 0, "classic-item", instance.id, false)


func _resolve_targeted_spell_item(state: GameState, content: RealmzContent, caster: CharacterState, instance: ItemInstance, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_id: String, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var effective_target_id := caster.id if spell.target_type == 5 else target_id
	var selection := _selection.spell_target_selection(state, content, effective_target_id)
	var field_center := state.combat.battlefield.actors.actor_position(caster.id) if spell.target_type == 5 else INVALID_COORDINATE
	var persistent_field: RefCounted = _context.fields().queue_persistent_field(state.combat, caster.id, spell, power_level, cast_level, rng, field_center, 0, 1) if spell.target_type == 5 else _context.fields().queue_single_actor_field(state, caster.id, effective_target_id, spell, power_level, cast_level, rng) if spell.target_type == 1 else null
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and persistent_field == null:
		return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"persistent_field_queue_failed", "The self-centered item field could not be queued.")
	var targeted := _context.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if targeted == null or not targeted.cast:
		return CombatFlowSpellRollback.item(state, rng, state_checkpoint, rng_checkpoint, &"item_spell_failed", "The item spell could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, targeted, rng, field_center, 1 if spell.target_type == 5 and persistent_field != null else 0, "classic-item", instance.id, false, [persistent_field] if persistent_field != null else [])


func character_item_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatItemOptionView]:
	var result: Array[CombatItemOptionView] = []
	if state == null or state.combat == null or state.combat.turns.active_actor_id() != caster_id:
		return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return result
	var staged_instance_id := state.combat.turns.staged_random_item_instance_id()
	for instance: ItemInstance in caster.inventory():
		var item := content.items.item_by_id(instance.definition_id)
		var spell := content.magic.spell_by_classic_id(item.special_2) if item != null else null
		if item == null or spell == null or not staged_instance_id.is_empty() and staged_instance_id != instance.id:
			continue
		var authored_power := absi(item.special_1)
		var power_level := state.combat.turns.staged_random_item_power(caster_id, instance.id) if authored_power == 8 else authored_power
		if authored_power == 8 and power_level == 0:
			if probe_character_item_spell(state, content, caster_id, "", instance.id).allowed:
				result.append(CombatItemOptionView.new(instance, item, spell, 0, null, "Roll power before targeting", &"random_power"))
			continue
		var power_options := _character_item_spell_options_for_power(state, content, caster, instance, item, spell, power_level)
		for option: CombatItemOptionView in power_options:
			option.power_staged = authored_power == 8
		result.append_array(power_options)
	for instance: ItemInstance in caster.inventory():
		var item := content.items.item_by_id(instance.definition_id)
		if item == null or item.special_1 != -23 or not staged_instance_id.is_empty() and staged_instance_id != instance.id:
			continue
		var probe := _context.inventory.classic_door_item_probe(caster, instance, item, content.characters.race_by_id(caster.race_id), content.characters.caste_by_id(caster.caste_id), true, content.scenario.program_by_id("xap:%d" % item.special_5) != null)
		if probe.allowed:
			result.append(CombatItemOptionView.new(instance, item, null, 0, null, "Scenario action", &"automatic"))
	return result


func _character_item_spell_options_for_power(state: GameState, content: RealmzContent, caster: CharacterState, instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition, power_level: int) -> Array[CombatItemOptionView]:
	var result: Array[CombatItemOptionView] = []
	if spell.target_type == 0:
		if probe_character_item_spell(state, content, caster.id, "", instance.id).allowed: result.append(CombatItemOptionView.new(instance, item, spell, power_level, null, "Choose up to %d open spaces" % power_level, &"coordinate_sequence", 0, state.combat.battlefield.actors.actor_position(caster.id), [], [], [], power_level) if CombatFlowSummoning.is_summon_spell(spell) else CombatItemOptionView.new(instance, item, spell, power_level, null, "Choose up to %d actors" % power_level, &"sequence", 0, INVALID_COORDINATE, [], [], [], power_level, _selection.character_actor_spell_candidates(state, content, caster, spell, power_level)))
		return result
	if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) or ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell):
		if probe_character_item_spell(state, content, caster.id, "", instance.id).allowed: result.append(CombatItemOptionView.new(instance, item, spell, power_level, null, "Choose battlefield destination", &"area", 0, state.combat.battlefield.actors.actor_position(caster.id), [Vector2i.ZERO]))
		return result
	if spell.target_type in [3, 4]:
		if probe_character_item_spell(state, content, caster.id, "", instance.id).allowed:
			var shape := _context.spell_areas.shape_for(spell, power_level)
			result.append(CombatItemOptionView.new(instance, item, spell, power_level, null, "Choose battlefield point", &"area", shape, state.combat.battlefield.actors.actor_position(caster.id), _context.spell_areas.pattern(shape), _selection.legal_area_spell_target_coordinates(state, content, caster.id, spell, power_level, shape), _context.spell_areas.rotation_patterns(spell, power_level)))
		return result
	if spell.target_type in [9, 10, 12]:
		if probe_character_item_spell(state, content, caster.id, "", instance.id).allowed:
			result.append(CombatItemOptionView.new(instance, item, spell, power_level, null, _selection.group_spell_target_label(spell.target_type), &"automatic"))
		return result
	if spell.target_type in [5, 7]:
		if probe_character_item_spell(state, content, caster.id, caster.id, instance.id).allowed:
			result.append(CombatItemOptionView.new(instance, item, spell, power_level, _selection.spell_target_view(state, content, caster.id), "Party" if spell.target_type == 7 else "Self", &"automatic"))
		return result
	for target: CombatSpellTargetView in _selection.character_actor_spell_candidates(state, content, caster, spell, power_level):
		if probe_character_item_spell(state, content, caster.id, target.id, instance.id).allowed:
			result.append(CombatItemOptionView.new(instance, item, spell, power_level, target))
	return result


func character_item_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if not character_item_spell_options(state, content, caster_id).is_empty():
		return ""
	if state == null or state.combat == null or state.combat.turns.active_actor_id() != caster_id:
		return "Only the active character may use an item."
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.inventory().is_empty():
		return "The active character carries no items."
	for instance: ItemInstance in caster.inventory():
		var item := content.items.item_by_id(instance.definition_id)
		var spell := content.magic.spell_by_classic_id(item.special_2) if item != null else null
		if item != null and spell != null:
			var probe := probe_character_item_spell(state, content, caster_id, caster_id if spell.target_type in [5, 7] else "", instance.id)
			if not probe.allowed:
				return probe.reason_text
	return "No carried item has a supported Classic combat use."


static func inventory_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


static func item_use_reason_code(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> StringName:
	if instance == null or item == null:
		return &"unknown_item_instance"
	if instance.charges == 0:
		return &"item_has_no_charges"
	if item.special_2 <= 1100:
		return &"item_has_no_spell_effect"
	if spell == null:
		return &"unknown_item_spell"
	return &"item_cannot_be_used"


static func item_used_event(caster_id: String, instance_id: String, item: ItemDefinition, spell: SpellDefinition, power_level: int, caster: CharacterState) -> DomainEvent:
	var remaining := -1
	var dropped := true
	for instance: ItemInstance in caster.inventory():
		if instance.id == instance_id:
			remaining = instance.charges
			dropped = false
			break
	return DomainEvent.new(&"item_used", {"characterId": caster_id, "instanceId": instance_id, "itemId": item.id, "spellId": spell.id, "power": power_level, "chargesRemaining": remaining, "droppedOnEmpty": dropped, "source": "classic"})


func cast_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, rng: RealmzRng, target_coordinate: Vector2i = Vector2i(-100_000, -100_000), rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	var spell := content.magic.spell_by_id(spell_id) if content != null else null
	var effective_target_id := caster_id if spell != null and spell.target_type == 5 else target_id
	var probe := _selection.probe_character_spell_cast(state, content, caster_id, effective_target_id, spell_id, power_level, target_coordinate, rotation, target_ids, target_coordinates)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var combat := state.combat
	var caster := state.party.character_by_id(caster_id)
	spell = content.magic.spell_by_id(spell_id)
	var cast_level := spell.classic_tier()
	if CombatFlowSummoning.is_summon_spell(spell):
		return _context.summoning().cast_character_summon(state, content, caster, spell, power_level, rng, target_coordinates)
	if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell):
		return _context.phase().cast_character_phase(state, content, caster, spell, power_level, cast_level, rng, target_coordinate)
	if spell.target_type in [3, 4]:
		if target_coordinate == INVALID_COORDINATE:
			return CombatFlowResult.failed(&"area_target_required", "A fixed or power area spell requires a battlefield coordinate.")
		var state_checkpoint := state.to_data()
		var rng_checkpoint := rng.checkpoint()
		_context.actions().prepare_character_turn(combat, caster)
		combat.turns.invalidate_undo()
		var area_result := _resolution.cast_area(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, rotation)
		return area_result if area_result.ok else CombatFlowSpellRollback.character_area(state, rng, state_checkpoint, rng_checkpoint, area_result.error_code, area_result.error_message)
	var targeted_state_checkpoint := state.to_data() if spell.target_type == 5 and ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) or ClassicSpellConditionRules.is_combat_single_actor_field_spell(spell) else {}
	var targeted_rng_checkpoint := rng.checkpoint() if not targeted_state_checkpoint.is_empty() else {}
	_context.actions().prepare_character_turn(combat, caster)
	combat.turns.invalidate_undo()
	if spell.target_type in [9, 10, 12]:
		return _resolution.cast_group(state, content, caster, spell, power_level, cast_level, rng)
	if spell.target_type == 7:
		var party := _context.magic.resolve_character_group_spell(caster, [], [], [], spell, power_level, cast_level, rng, true, true)
		return CombatFlowResult.failed(&"spell_cast_failed", "The party spell could not be cast with the available spell points.") if party == null or not party.cast else _resolution.commit(state, content, caster, spell, power_level, cast_level, party, rng)
	if spell.target_type == 0:
		return _cast_learned_repeated_spell(state, content, caster, spell, power_level, cast_level, rng, target_ids)
	if spell.target_type == 6:
		var ray_selections := _resolution.ray_selections(state, content, caster.id, target_id, spell)
		var ray := _context.magic.resolve_character_ray_spell(caster, ray_selections, spell, power_level, cast_level, rng)
		if ray == null or not ray.cast:
			return CombatFlowResult.failed(&"spell_cast_failed", "The ray spell could not be cast with the available spell points.")
		return _resolution.commit(state, content, caster, spell, power_level, cast_level, ray, rng)
	var selection := _selection.spell_target_selection(state, content, effective_target_id)
	if selection == null:
		return CombatFlowResult.failed(&"spell_target_unavailable", "The selected combatant is unavailable.")
	var field_center := combat.battlefield.actors.actor_position(caster.id) if spell.target_type == 5 else INVALID_COORDINATE
	var persistent_field: RefCounted = _context.fields().queue_persistent_field(combat, caster.id, spell, power_level, cast_level, rng, field_center, 0, 1) if spell.target_type == 5 else _context.fields().queue_single_actor_field(state, caster.id, effective_target_id, spell, power_level, cast_level, rng) if spell.target_type == 1 else null
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and persistent_field == null:
		return CombatFlowSpellRollback.character_targeted(state, rng, targeted_state_checkpoint, targeted_rng_checkpoint, &"persistent_field_queue_failed", "The self-centered spell field could not be queued.")
	var targeted := _context.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, true, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if targeted == null or not targeted.cast:
		return CombatFlowSpellRollback.character_targeted(state, rng, targeted_state_checkpoint, targeted_rng_checkpoint, &"spell_cast_failed", "The spell could not be cast with the available spell points.") if not targeted_state_checkpoint.is_empty() else CombatFlowResult.failed(&"spell_cast_failed", "The spell could not be cast with the available spell points.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, targeted, rng, field_center, 1 if spell.target_type == 5 and persistent_field != null else 0, "classic", "", true, [persistent_field] if persistent_field != null else [])


func _cast_learned_repeated_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_ids: Array[String]) -> CombatFlowResult:
	var selections: Array[SpellTargetSelection] = []
	for selected_id: String in target_ids:
		var repeated_selection := _selection.spell_target_selection(state, content, selected_id)
		if repeated_selection == null:
			return CombatFlowResult.failed(&"spell_target_unavailable", "A selected repeated-spell target is unavailable.")
		selections.append(repeated_selection)
	var repeated_fields: Array[RefCounted] = []
	var repeated := _context.magic.resolve_character_repeated_spell(caster, selections, spell, power_level, cast_level, rng, true, _context.fields().repeated_field_callback(state, spell, caster.id, target_ids, power_level, cast_level, rng, repeated_fields), content.items.definitions())
	if repeated == null or not repeated.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The repeated-target spell could not be cast with the available spell points.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, repeated, rng, INVALID_COORDINATE, 0, "classic", "", true, repeated_fields)


func ray_spell_actor_ids(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition) -> Array[String]:
	return _resolution.ray_actor_ids(state, content, caster_id, target_id, spell)


func probe_character_scroll_cast(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int, target_id: String = "", target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_turn", "Scroll use requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_turn", "Only the active character may use a scroll in combat.")
	if not combat.spell_runtime.pending_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.current_health <= 0 or caster.conditions.is_active(ConditionRules.ANIMATED):
		return CombatSpellCastProbe.blocked(&"scroll_user_unavailable", "The active character cannot use a scroll.")
	if not _context.equipment.has_equipped_scroll_case(caster, content):
		return CombatSpellCastProbe.blocked(&"scroll_case_not_equipped", "Equip a scroll case before using its spells.")
	var scroll := caster.scroll_at(scroll_slot)
	var spell := content.magic.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
	if scroll_slot < 0 or scroll_slot >= 5 or scroll == null or scroll.is_empty() or spell == null or scroll.power < 1 or scroll.power > 7:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_slot", "This scroll slot is empty or invalid.")
	if not spell.in_combat:
		return CombatSpellCastProbe.blocked(&"scroll_not_available_in_combat", "This scroll cannot be used in combat.")
	var repeated_target := spell.target_type == 0
	var phase_spell := ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell)
	var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
	var group_target := spell.target_type in [9, 10, 12]
	var area_target := spell.target_type in [3, 4]
	var self_target := spell.target_type in [5, 7]
	var actor_target: bool = not repeated_target and not group_target and not area_target and not summon_spell and not phase_spell
	var effective_target_id := caster_id if self_target else target_id
	if actor_target and _selection.spell_target_selection(state, content, effective_target_id) == null:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_target", "The selected combatant is unavailable.")
	if ClassicSpellDispositionRules.combat_scroll_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_scroll", ClassicSpellDispositionRules.unsupported_reason(spell, &"combat-scroll"))
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and not combat.spell_runtime.can_queue_persistent_field():
		return CombatSpellCastProbe.blocked(&"persistent_field_queue_limit", "Castle's persistent battlefield-field queue is full.")
	if repeated_target and spell.size != 0 and not summon_spell:
		return CombatSpellCastProbe.blocked(&"repeated_open_space_spell_unresolved", "Classic target type 0 with nonzero size selects open-space footprints for summoning or special behavior, not ordinary actors.")
	if area_target and _selection.invalid_area_rotation(spell, rotation):
		return CombatSpellCastProbe.blocked(&"invalid_area_rotation", "This Classic area spell does not support the selected orientation.")
	var cast_level := spell.classic_tier()
	if cast_level < 0 or cast_level > 6:
		return CombatSpellCastProbe.blocked(&"invalid_classic_spell_tier", "The scroll spell ID does not encode a valid Classic tier.")
	if summon_spell:
		return _context.summoning().probe_choice(state, content, caster_id, spell, scroll.power) if target_coordinates.is_empty() else _context.summoning().probe_coordinates(state, content, caster_id, spell, scroll.power, target_coordinates)
	if phase_spell: return CombatSpellCastProbe.permitted() if target_coordinate == INVALID_COORDINATE else _context.phase().probe_destination(state, content, caster_id, spell, scroll.power, target_coordinate)
	if repeated_target:
		return _probe_repeated_scroll_spell(state, content, caster, spell, scroll.power, target_ids)
	elif area_target:
		return _probe_scroll_area_spell(state, content, caster, spell, scroll.power, target_coordinate, rotation)
	elif group_target:
		return _probe_scroll_group_spell(state, caster, spell)
	elif not _selection.spell_actor_target_is_valid(state, content, caster.id, effective_target_id, spell, scroll.power):
		return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "The target is outside the Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func _probe_repeated_scroll_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, target_ids: Array[String]) -> CombatSpellCastProbe:
	if target_ids.size() > power_level:
		return CombatSpellCastProbe.blocked(&"too_many_scroll_targets", "A repeated scroll may select at most one distinct actor per power level.")
	var seen: Dictionary = {}
	for selected_id: String in target_ids:
		if selected_id.is_empty() or seen.has(selected_id):
			return CombatSpellCastProbe.blocked(&"invalid_repeated_scroll_targets", "Repeated scroll targets must be nonempty and distinct.")
		seen[selected_id] = true
		if _selection.spell_target_selection(state, content, selected_id) == null:
			return CombatSpellCastProbe.blocked(&"invalid_scroll_target", "A selected repeated-scroll actor is unavailable.")
		if not _selection.spell_actor_target_is_valid(state, content, caster.id, selected_id, spell, power_level):
			return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "A selected repeated-scroll actor is outside the Classic spell range or line of sight.")
	if target_ids.is_empty() and _selection.character_actor_spell_candidates(state, content, caster, spell, power_level).is_empty():
		return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "No actor is available within this repeated scroll's Classic range and line of sight.")
	return CombatSpellCastProbe.permitted()


func _probe_scroll_area_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, target_coordinate: Vector2i, rotation: int) -> CombatSpellCastProbe:
	var shape := _context.spell_areas.shape_for(spell, power_level, rotation)
	if _context.spell_areas.pattern(shape).is_empty():
		return CombatSpellCastProbe.blocked(&"invalid_scroll_area_shape", "The scroll references an unavailable Classic Data AD area mask.")
	if target_coordinate == INVALID_COORDINATE:
		return CombatSpellCastProbe.permitted()
	if not _context.spell_areas.pattern_fits(target_coordinate, shape):
		return CombatSpellCastProbe.blocked(&"scroll_area_outside_battlefield", "The complete Classic area mask must remain inside the validated battlefield.")
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	if terrain_set == null or not _context.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster.id, target_coordinate, maximum_range, spell.range_min + spell.range_max > 0):
		return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "The area center is outside the Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func _probe_scroll_group_spell(state: GameState, caster: CharacterState, spell: SpellDefinition) -> CombatSpellCastProbe:
	var group_count := 0
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id) and _selection.group_target_matches(spell.target_type, character.traitor, caster.traitor):
			group_count += 1
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and state.combat.battlefield.actors.has_actor(monster.id) and _selection.group_target_matches(spell.target_type, monster.traitor, caster.traitor):
			group_count += 1
	if group_count == 0:
		return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "The scroll has no available group target.")
	return CombatSpellCastProbe.permitted()


func use_combat_scroll(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int, target_id: String, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	var probe := probe_character_scroll_cast(state, content, caster_id, scroll_slot, target_id, target_coordinate, rotation, target_ids, target_coordinates)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var caster := state.party.character_by_id(caster_id)
	var scroll := caster.scroll_at(scroll_slot)
	var spell := content.magic.spell_by_id(scroll.spell_id)
	if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) and target_coordinate == INVALID_COORDINATE: return CombatFlowResult.failed(&"scroll_area_target_required", "Choose a battlefield destination for Phase.")
	var power_level := scroll.power
	var cast_level := spell.classic_tier()
	var result := _resolve_combat_scroll(state, content, caster, spell, power_level, cast_level, rng, target_id, target_coordinate, rotation, target_ids, target_coordinates, state_checkpoint, rng_checkpoint)
	if not result.ok:
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, result.error_code, result.error_message)
	var committed_caster := state.party.character_by_id(caster_id)
	if committed_caster == null or not committed_caster.clear_scroll(scroll_slot):
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_commit_failed", "The resolved scroll could not be removed from its case.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"scroll_used", {"characterId": caster_id, "slot": scroll_slot, "spellId": spell.id, "power": power_level, "source": "classic-combat"})]
	events.append_array(result.events)
	result.events = events
	return result


func _resolve_combat_scroll(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_id: String, target_coordinate: Vector2i, rotation: int, target_ids: Array[String], target_coordinates: Array[Vector2i], state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	if CombatFlowSummoning.is_summon_spell(spell):
		if target_coordinates.is_empty():
			return CombatFlowResult.failed(&"summon_target_required", "Choose at least one open battlefield space for the summon scroll.")
		return _context.summoning().cast_character_summon(state, content, caster, spell, power_level, rng, target_coordinates, "classic-scroll", false, false)
	if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell):
		return _context.phase().cast_character_phase(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, false, "classic-scroll", false)
	_context.actions().prepare_character_turn(state.combat, caster)
	state.combat.turns.invalidate_undo()
	if spell.target_type in [3, 4]:
		return _resolve_area_scroll(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, rotation, state_checkpoint, rng_checkpoint)
	if spell.target_type == 7:
		var party := _context.magic.resolve_character_group_spell(caster, [], [], [], spell, power_level, cast_level, rng, true, false)
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The party scroll could not be resolved.") if party == null or not party.cast else _resolution.commit(state, content, caster, spell, power_level, cast_level, party, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	if spell.target_type in [9, 10, 12]:
		return _resolve_group_scroll(state, content, caster, spell, power_level, cast_level, rng, state_checkpoint, rng_checkpoint)
	if spell.target_type == 0:
		return _resolve_repeated_scroll(state, content, caster, spell, power_level, cast_level, rng, target_ids, state_checkpoint, rng_checkpoint)
	if spell.target_type == 6:
		var ray_selections := _resolution.ray_selections(state, content, caster.id, target_id, spell)
		var ray := _context.magic.resolve_character_ray_spell(caster, ray_selections, spell, power_level, cast_level, rng, false)
		if ray == null or not ray.cast:
			return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The ray scroll could not be resolved.")
		return _resolution.commit(state, content, caster, spell, power_level, cast_level, ray, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	return _resolve_targeted_scroll(state, content, caster, spell, power_level, cast_level, rng, target_id, state_checkpoint, rng_checkpoint)


func _resolve_area_scroll(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_coordinate: Vector2i, rotation: int, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
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
	var area := _context.magic.resolve_character_group_spell(caster, area_targets.get("characters", []), area_targets.get("monsters", []), area_targets.get("definitions", []), spell, power_level, cast_level, rng, true, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if area == null or not area.cast:
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The area scroll could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, area, rng, target_coordinate, shape, "classic-scroll", "", false, [persistent_field])


func _resolve_group_scroll(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var group_targets := _resolution.group_targets(state, content, caster, spell)
	if not bool(group_targets.get("ok", false)):
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_target_unavailable", String(group_targets.get("error", "A scroll target is unavailable.")))
	var group := _context.magic.resolve_character_group_spell(caster, group_targets.get("characters", []), group_targets.get("monsters", []), group_targets.get("definitions", []), spell, power_level, cast_level, rng, false, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if group == null or not group.cast:
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The group scroll could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, group, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)


func _resolve_repeated_scroll(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_ids: Array[String], state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
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


func _resolve_targeted_scroll(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, target_id: String, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> CombatFlowResult:
	var effective_target_id := caster.id if spell.target_type == 5 else target_id
	var selection := _selection.spell_target_selection(state, content, effective_target_id)
	var field_center := state.combat.battlefield.actors.actor_position(caster.id) if spell.target_type == 5 else INVALID_COORDINATE
	var persistent_field: RefCounted = _context.fields().queue_persistent_field(state.combat, caster.id, spell, power_level, cast_level, rng, field_center, 0, 1) if spell.target_type == 5 else _context.fields().queue_single_actor_field(state, caster.id, effective_target_id, spell, power_level, cast_level, rng) if spell.target_type == 1 else null
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and persistent_field == null:
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"persistent_field_queue_failed", "The self-centered scroll field could not be queued.")
	var targeted := _context.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, false, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if targeted == null or not targeted.cast:
		return CombatFlowSpellRollback.scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The targeted scroll could not be resolved.")
	return _resolution.commit(state, content, caster, spell, power_level, cast_level, targeted, rng, field_center, 1 if spell.target_type == 5 and persistent_field != null else 0, "classic-scroll", "", false, [persistent_field] if persistent_field != null else [])
