## Runs deterministic monster phases, movement, spells, attacks, and retreat.

class_name CombatMonsterAutomation
extends RefCounted

const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2
const MONSTER_ATTACK_FALLBACK := 3
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const MAX_MONSTERS: int = 100
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)


class MonsterSpellTargetPlan:
	extends RefCounted

	var selections: Array[SpellTargetSelection] = []
	var target_ids: Array[String] = []
	var area_center := INVALID_COORDINATE
	var area_rotation := 0
	var area_shape := 0


var _context: CombatContext
var _ai_scoring: CombatAiScoring
var _monster_actions: CombatMonsterActions
var _occupancy: CombatOccupancyRules


func _init(context: CombatContext) -> void:
	_context = context
	_ai_scoring = CombatAiScoring.new(context)
	_monster_actions = CombatMonsterActions.new(context)
	_occupancy = CombatOccupancyRules.new(context)


func monster_actions() -> CombatMonsterActions:
	return _monster_actions


func process_monster_turns(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	if combat == null: return
	var spell_runtime := combat.spell_runtime
	var turns := combat.turns
	var roster := combat.roster
	var actor_statuses := combat.actor_statuses
	if not spell_runtime.pending_death_macro_id().is_empty(): return
	# The order may grow while this loop is active when a monster casts a
	# multi-summon or a death macro adds combatants. Bound the scan by the
	# authoritative actor capacities instead of the order's stale entry count.
	var guard := MAX_MONSTERS + state.party.characters().size()
	while guard > 0 and not combat.completed and spell_runtime.pending_death_macro_id().is_empty():
		var actor_id := turns.active_actor_id()
		var monster := roster.monster_by_id(actor_id)
		if monster == null:
			var charmed_actor := state.party.character_by_id(actor_id)
			if charmed_actor != null and (combat.battlefield == null or not combat.battlefield.actors.has_actor(charmed_actor.id)):
				_context.rounds().advance_turn(state, content, rng, events)
				guard -= 1
				continue
			if charmed_actor == null or not charmed_actor.traitor:
				if charmed_actor != null and charmed_actor.current_health > 0:
					_context.actions().prepare_character_turn(combat, charmed_actor)
				break
			if charmed_actor.current_health > 0 and process_charmed_character_turn(state, content, charmed_actor, rng, events):
				_context.rounds().advance_turn(state, content, rng, events)
				return
			_context.rounds().advance_turn(state, content, rng, events)
			if _context.rounds().finish_if_resolved(state, content, events):
				break
			guard -= 1
			continue
		if monster.current_health <= 0:
			_context.rounds().advance_turn(state, content, rng, events)
			guard -= 1
			continue
		if turns.active_turn == null:
			actor_statuses.set_guarding(monster.id, true)
		if monster.conditions.is_active(ConditionRules.HELPLESS):
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "incapacitated"}))
			_context.rounds().advance_turn(state, content, rng, events)
			guard -= 1
			continue
		var definition := content.combat.monster_by_id(monster.definition_id)
		if definition == null:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "unavailable_definition"}))
			_context.rounds().advance_turn(state, content, rng, events)
			guard -= 1
			continue
		var active_turn := turns.begin_active_turn()
		if active_turn.movement_remaining < 0:
			active_turn.movement_remaining = _monster_actions.movement_allowance(monster, definition)
		if active_turn.target_id.is_empty() and active_turn.attack_index == 0:
			active_turn.target_id = monster.target_id
		if active_turn.action.is_empty():
			active_turn.action = _ai_scoring.choose_monster_action(state, content, monster, definition, rng)
		if _process_selected_monster_action(state, content, monster, definition, active_turn, rng, events) != MONSTER_ATTACK_COMPLETED:
			return
		_context.rounds().advance_turn(state, content, rng, events)
		if _context.rounds().finish_if_resolved(state, content, events):
			break
		guard -= 1


func _process_selected_monster_action(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	match active_turn.action:
		&"advance":
			return _process_advance_action(state, content, monster, definition, active_turn, rng, events)
		&"missile":
			return _process_missile_action(state, content, monster, definition, active_turn, rng, events)
		&"cast":
			return _process_cast_action(state, content, monster, definition, active_turn, rng, events)
		&"retreat":
			return process_monster_retreat(state, content, monster, definition, active_turn, rng, events)
		_:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": String(active_turn.action)}))
			return MONSTER_ATTACK_COMPLETED


func _process_advance_action(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	if monster.conditions.is_active(ConditionRules.SPEEDY):
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "monster-speedy-cadence-unresolved"}))
		return MONSTER_ATTACK_COMPLETED
	if monster.conditions.value(ConditionRules.TANGLED) < 0:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "permanent-tangle-movement-unresolved"}))
		return MONSTER_ATTACK_COMPLETED
	return _advance_then_retry_cast(state, content, monster, definition, active_turn, rng, events)


func _process_missile_action(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var result := process_monster_projectile(state, content, monster, definition, active_turn, rng, events)
	if result != MONSTER_ATTACK_FALLBACK:
		return result
	active_turn.action = _ai_scoring.choose_monster_action(state, content, monster, definition, rng, false)
	if active_turn.action == &"cast":
		result = process_monster_cast(state, content, monster, definition, active_turn, rng, events)
		if result != MONSTER_ATTACK_FALLBACK:
			return result
	active_turn.action = &"advance"
	return _advance_then_retry_cast(state, content, monster, definition, active_turn, rng, events)


func _process_cast_action(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var result := process_monster_cast(state, content, monster, definition, active_turn, rng, events)
	if result != MONSTER_ATTACK_FALLBACK:
		return result
	active_turn.action = &"advance"
	return _advance_then_retry_cast(state, content, monster, definition, active_turn, rng, events)


func _advance_then_retry_cast(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var result := process_monster_advance(state, content, monster, definition, active_turn, rng, events)
	if result == MONSTER_ATTACK_COMPLETED and monster_can_retry_cast(state, monster, definition, active_turn):
		return process_monster_cast(state, content, monster, definition, active_turn, rng, events)
	return result


func process_monster_cast(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	active_turn.monster_cast_attempt_count += 1
	if state.monster_spellcasting_blocked or state.combat.actor_statuses.was_attacked(monster.id) or definition.magic_attack_count <= 0:
		return MONSTER_ATTACK_FALLBACK
	for condition: int in [ConditionRules.STUPID, ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS]:
		if monster.conditions.is_active(condition):
			return MONSTER_ATTACK_FALLBACK
	var did_cast := active_turn.spell_cast_count > 0
	while active_turn.spell_cast_count < definition.magic_attack_count:
		var ai_plan: Dictionary = _ai_scoring.best_monster_spell_plan(state, content, monster, definition)
		if ai_plan.is_empty():
			break
		var spell := content.magic.spell_by_id(String(ai_plan["spellId"]))
		var range_power := int(ai_plan["power"])
		var cost_power := range_power
		var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
		if summon_spell:
			var target_coordinates: Array[Vector2i] = []
			target_coordinates.assign(ai_plan.get("targetCoordinates", []))
			if target_coordinates.is_empty():
				break
			state.combat.actor_statuses.set_guarding(monster.id, false)
			active_turn.movement_remaining = 0
			var casts_before := active_turn.spell_cast_count
			var summon_result: CombatFlowResult = _context.summoning().cast_monster_summon(state, content, monster, spell, cost_power, rng, target_coordinates)
			if not summon_result.ok:
				return MONSTER_ATTACK_COMPLETED if did_cast else MONSTER_ATTACK_FALLBACK
			events.append_array(summon_result.events)
			if active_turn.spell_cast_count == casts_before:
				return MONSTER_ATTACK_COMPLETED if did_cast else MONSTER_ATTACK_FALLBACK
			did_cast = true
			continue
		var target_plan := _prepare_monster_spell_targets(state, content, monster, spell, cost_power, ai_plan)
		if target_plan.selections.is_empty():
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		var cast_level := spell.classic_tier()
		if cast_level < 0 or cast_level > 6:
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": spell.id, "reason": "invalid-classic-spell-tier"}))
			if did_cast:
				break
			return MONSTER_ATTACK_COMPLETED
		state.combat.actor_statuses.set_guarding(monster.id, false)
		active_turn.movement_remaining = 0
		if not _execute_monster_spell(state, content, monster, definition, spell, cost_power, range_power, cast_level, target_plan, rng, events):
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		active_turn.spell_cast_count += 1
		did_cast = true
	return _finish_monster_cast(state, content, monster, did_cast, events)


func _prepare_monster_spell_targets(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, power: int, ai_plan: Dictionary) -> MonsterSpellTargetPlan:
	var plan := MonsterSpellTargetPlan.new()
	if spell.target_type in [3, 4]:
		plan.area_center = ai_plan.get("coordinate", INVALID_COORDINATE)
		plan.area_rotation = int(ai_plan.get("rotation", 0))
		plan.area_shape = _context.spell_areas.shape_for(spell, power, plan.area_rotation)
		plan.selections = _monster_area_spell_selections(state, content, plan.area_center, plan.area_shape)
		return plan
	if spell.target_type == 5:
		plan.area_center = state.combat.battlefield.actors.actor_position(monster.id)
		plan.area_shape = 1
	for target_id: String in ai_plan["targetIds"]:
		plan.target_ids.append(target_id)
	if spell.target_type == 6:
		plan.target_ids = _context.magic_flow().ray_spell_actor_ids(state, content, monster.id, plan.target_ids[0], spell)
	for target_id: String in plan.target_ids:
		var selection := _monster_spell_target_selection(state, content, target_id)
		if selection != null:
			plan.selections.append(selection)
	return plan


func _execute_monster_spell(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, cost_power: int, range_power: int, cast_level: int, target_plan: MonsterSpellTargetPlan, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	var created_fields: Array[RefCounted] = []
	var persistent_field: RefCounted = null
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell):
		persistent_field = _context.fields().queue_persistent_field(state.combat, monster.id, spell, cost_power, cast_level, rng, target_plan.area_center, target_plan.area_rotation, target_plan.area_shape)
		if persistent_field == null:
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": spell.id, "reason": "persistent-field-queue-limit"}))
			return false
	if ClassicSpellConditionRules.is_combat_single_actor_field_spell(spell):
		var actor_field: RefCounted = _context.fields().queue_single_actor_field(state, monster.id, target_plan.target_ids[0], spell, cost_power, cast_level, rng)
		if actor_field != null:
			created_fields.append(actor_field)
	var resolutions := _resolve_monster_spell(state, content, monster, definition, spell, cost_power, cast_level, target_plan, rng, created_fields)
	if resolutions == null or not resolutions.cast:
		return false
	if persistent_field != null:
		created_fields.append(persistent_field)
	_context.fields().append_created_events(events, created_fields, "classic-monster")
	CombatSpellEventBuilder.append_sound(events, spell.sound_start, "classic-monster-spell-start")
	CombatSpellEventBuilder.append_cast(events, monster.id, spell, resolutions, target_plan.area_center, target_plan.area_shape, "classic-monster")
	_append_monster_spell_resolution_events(state, content, monster, spell, resolutions, cost_power, range_power, cast_level, target_plan.area_center, target_plan.area_shape, events)
	return true


func _resolve_monster_spell(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, power: int, cast_level: int, target_plan: MonsterSpellTargetPlan, rng: RealmzRng, created_fields: Array[RefCounted]) -> GroupSpellResolution:
	if spell.target_type in [3, 4]:
		return _context.magic.resolve_monster_group_spell(monster, definition, target_plan.selections, spell, power, cast_level, rng, true, true, _monster_polymorph_context(state, content))
	if spell.target_type in [9, 10, 12]:
		return _context.magic.resolve_monster_group_spell(monster, definition, target_plan.selections, spell, power, cast_level, rng, false, true, _monster_polymorph_context(state, content))
	if spell.target_type == 0:
		var callback: Callable = _context.fields().repeated_field_callback(state, spell, monster.id, target_plan.target_ids, power, cast_level, rng, created_fields)
		return _context.magic.resolve_monster_repeated_spell(monster, definition, target_plan.selections, spell, power, cast_level, rng, callback)
	if spell.target_type == 6:
		return _context.magic.resolve_monster_ray_spell(monster, definition, target_plan.selections, spell, power, cast_level, rng)
	return _context.magic.resolve_monster_targeted_spell(monster, definition, target_plan.selections[0], spell, power, cast_level, rng, _monster_polymorph_context(state, content))


static func _monster_polymorph_context(state: GameState, content: RealmzContent) -> MonsterPolymorphContext:
	return MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day())


func _append_monster_spell_resolution_events(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, resolutions: GroupSpellResolution, cost_power: int, range_power: int, cast_level: int, area_center: Vector2i, area_shape: int, events: Array[DomainEvent]) -> void:
	for index: int in resolutions.resolutions.size():
		var resolution := resolutions.resolutions[index]
		var resolved_target_id := resolutions.target_ids[index]
		var selected_target_id := resolutions.selected_target_ids[index]
		var target_kind := resolutions.target_kinds[index]
		var reflected := resolutions.reflected_targets[index]
		if resolution.damage > 0 or (resolution.damage < 0 and target_kind == &"monster"):
			state.combat.actor_statuses.mark_attacked(resolved_target_id)
		CombatSpellEventBuilder.append_projectile(events, monster.id, resolved_target_id, spell, "classic-monster")
		CombatSpellEventBuilder.append_sound(events, spell.sound_end, "classic-monster-spell-result")
		var payload := {"actorId": monster.id, "targetId": resolved_target_id, "selectedTargetId": selected_target_id, "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": cost_power, "rangePower": range_power, "classicTier": cast_level, "reflected": reflected, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": "classic-monster", "detectedMagicItemCount": resolution.detected_magic_item_count}
		if resolution.spell_point_delta != 0 or ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell):
			payload["spellPointDelta"] = resolution.spell_point_delta
		if resolution.cleared_condition >= 0:
			payload["clearedCondition"] = resolution.cleared_condition
		if resolution.applied_condition >= 0:
			payload["appliedCondition"] = resolution.applied_condition
		if resolution.allegiance_changed:
			payload["traitorBefore"] = resolution.target_traitor_before
			payload["traitorAfter"] = resolution.target_traitor_after
		if not resolution.transformed_definition_after.is_empty():
			payload["transformedDefinitionBefore"] = resolution.transformed_definition_before
			payload["transformedDefinitionAfter"] = resolution.transformed_definition_after
		if area_shape > 0:
			payload["areaCenter"] = [area_center.x, area_center.y]
			payload["areaShape"] = area_shape
		CombatSpellEventBuilder.append_resolution_effect(payload, spell, index, resolutions.resolutions.size(), resolution.target_defeated)
		events.append(DomainEvent.new(&"combat_spell_resolved", payload))
		if not resolution.target_defeated:
			continue
		if target_kind == &"character":
			_context.actions().mark_character_bleeding(state, state.party.character_by_id(resolved_target_id), true)
			remove_defeated_position(state.combat, resolved_target_id, true)
		else:
			_handle_monster_spell_defeat(state, content, monster, resolved_target_id, events)


func _handle_monster_spell_defeat(state: GameState, content: RealmzContent, caster: MonsterState, target_id: String, events: Array[DomainEvent]) -> void:
	var defeated_monster := state.combat.roster.monster_by_id(target_id)
	var defeated_definition := content.combat.monster_by_id(defeated_monster.definition_id) if defeated_monster != null else null
	var queued = _context.actions().events().queue_spell_death_macro(state.combat, defeated_monster, defeated_definition)
	if not queued and defeated_definition != null and defeated_definition.death_macro > 0:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": caster.id, "action": "cast", "targetId": target_id, "reason": "spell-death-macro-queue-limit"}))
	# Castle continues after reflection kills the caster, so retain its anchor until
	# the spell sequence and queued death macros have both finished.
	remove_defeated_position(state.combat, target_id, not queued and target_id != caster.id)


func _finish_monster_cast(state: GameState, content: RealmzContent, monster: MonsterState, did_cast: bool, events: Array[DomainEvent]) -> int:
	if not state.combat.spell_runtime.pending_death_macro_id().is_empty():
		if not state.combat.spell_runtime.begin_death_macro_sequence(monster.id, true) or not _context.actions().events().request_next_spell_death_macro(state.combat, content, events):
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "reason": "invalid-spell-death-macro-queue"}))
			return MONSTER_ATTACK_COMPLETED
		return MONSTER_ATTACK_DEATH_MACRO
	if monster.current_health <= 0:
		remove_defeated_position(state.combat, monster.id, true)
	return MONSTER_ATTACK_COMPLETED if did_cast else MONSTER_ATTACK_FALLBACK


func _monster_area_spell_selections(state: GameState, content: RealmzContent, center: Vector2i, shape: int) -> Array[SpellTargetSelection]:
	var selected_ids: Dictionary = {}
	for offset: Vector2i in _context.spell_areas.pattern(shape):
		var actor_id := state.combat.battlefield.actors.actor_at(center + offset)
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var result: Array[SpellTargetSelection] = []
	for character: CharacterState in state.party.characters():
		if selected_ids.has(character.id) and character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id):
			result.append(SpellTargetSelection.for_character(character))
	for monster: MonsterState in state.combat.roster.monsters():
		if not selected_ids.has(monster.id) or monster.current_health <= 0 or not state.combat.battlefield.actors.has_actor(monster.id) or monster.magic_resistance > 100:
			continue
		var definition := content.combat.monster_by_id(monster.definition_id)
		if definition != null:
			result.append(SpellTargetSelection.for_monster(monster, definition))
	return result


static func _monster_spell_target_selection(state: GameState, content: RealmzContent, target_id: String) -> SpellTargetSelection:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return SpellTargetSelection.for_character(character)
	var monster := state.combat.roster.monster_by_id(target_id)
	var definition := content.combat.monster_by_id(monster.definition_id) if monster != null else null
	return SpellTargetSelection.for_monster(monster, definition) if definition != null else null


static func monster_can_retry_cast(state: GameState, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState) -> bool:
	return definition.cast_percent != 0 and not active_turn.physical_action_committed and active_turn.spell_cast_count == 0 and active_turn.monster_cast_attempt_count < 2 and monster.current_health > 0 and not state.combat.actor_statuses.was_attacked(monster.id) and not state.monster_spellcasting_blocked


static func monster_spell_unavailable_reason(spell: SpellDefinition) -> String:
	if ClassicSpellDispositionRules.combat_monster_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return ClassicSpellDispositionRules.unsupported_reason(spell, &"combat-monster")
	var healing_spell := ClassicSpellConditionRules.is_combat_healing_spell(spell)
	var condition_cure := ClassicSpellConditionRules.is_combat_condition_cure_spell(spell)
	var condition_effect := ClassicSpellConditionRules.is_combat_condition_effect_spell(spell)
	var spell_point_restore := ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell)
	var destroy_magic := ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell)
	var charm_spell := ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell)
	if spell.cannot == 4 and not healing_spell and not condition_cure and not condition_effect and not spell_point_restore and not destroy_magic and not charm_spell:
		return "monster-spell-friendly-target-unresolved"
	return ""


static func is_source_backed_combat_healing_spell(spell: SpellDefinition) -> bool:
	return ClassicSpellConditionRules.is_combat_healing_spell(spell)


func process_monster_advance(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var terrain_set := _monster_actions.battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "missing-battle-terrain"}))
		active_turn.movement_remaining = 0
		return MONSTER_ATTACK_COMPLETED
	var contact_result := _begin_monster_contact(state, content, monster, rng, events)
	if contact_result == REACTION_WAITING:
		return MONSTER_ATTACK_WAITING
	if contact_result == REACTION_DEATH_MACRO:
		return MONSTER_ATTACK_DEATH_MACRO
	if contact_result == REACTION_MOVER_DEFEATED:
		return MONSTER_ATTACK_COMPLETED
	var operation_guard := 512
	while operation_guard > 0 and active_turn.attack_index < _monster_actions.attack_limit(definition):
		var adjacent_ids := hostile_adjacent_ids(state, monster.id)
		if not adjacent_ids.is_empty():
			if (active_turn.attack_index == 0 and not active_turn.physical_action_committed) or not adjacent_ids.has(active_turn.target_id):
				active_turn.target_id = _monster_actions.select_adjacent_target(state, monster, rng)
				monster.target_id = active_turn.target_id
			while active_turn.attack_index < _monster_actions.attack_limit(definition):
				var attack_result := resolve_monster_attack_row(state, content, monster, definition, active_turn.attack_index, active_turn, rng, events)
				if attack_result != MONSTER_ATTACK_COMPLETED:
					return attack_result
			return MONSTER_ATTACK_COMPLETED
		if active_turn.movement_remaining <= 0:
			return MONSTER_ATTACK_COMPLETED
		if not _refresh_monster_advance_target(state, monster, terrain_set, active_turn, rng):
			active_turn.movement_remaining = 0
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "no-visible-target"}))
			return MONSTER_ATTACK_COMPLETED
		var origin := combat.battlefield.actors.actor_position(monster.id)
		var probe := _probe_monster_advance_step(state, monster, terrain_set, active_turn, rng)
		if not probe.allowed:
			active_turn.target_id = ""
			monster.target_id = ""
			active_turn.movement_remaining = 0
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": String(probe.reason)}))
			return MONSTER_ATTACK_COMPLETED
		combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_MOVE, monster.id, origin, probe.destination, probe.movement_cost)
		combat.pending_reaction.set_phase(CombatReactionState.WITHDRAWAL, [])
		var movement_result = _context.reactions().continue_pending_reaction(state, content, rng, events)
		if movement_result == REACTION_WAITING:
			return MONSTER_ATTACK_WAITING
		if movement_result == REACTION_DEATH_MACRO:
			return MONSTER_ATTACK_DEATH_MACRO
		if movement_result == REACTION_MOVER_DEFEATED:
			return MONSTER_ATTACK_COMPLETED
		operation_guard -= 1
	if operation_guard == 0:
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "monster-movement-budget-exhausted"}))
	return MONSTER_ATTACK_COMPLETED


func _begin_monster_contact(state: GameState, content: RealmzContent, monster: MonsterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var origin := state.combat.battlefield.actors.actor_position(monster.id)
	state.combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_CONTACT, monster.id, origin, origin, 0)
	state.combat.pending_reaction.set_phase(CombatReactionState.GUARD_AFTER, _context.reactions().guarding_hostiles(state, monster.id))
	return _context.reactions().continue_pending_reaction(state, content, rng, events)


func _refresh_monster_advance_target(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, active_turn: CombatTurnState, rng: RealmzRng) -> bool:
	if _monster_actions.target_is_available(state, monster, active_turn.target_id):
		if not _context.battlefield.has_line_of_sight(state.combat.battlefield, terrain_set, monster.id, active_turn.target_id):
			active_turn.target_id = _monster_actions.scan_visible_target(state, monster, terrain_set)
	else:
		active_turn.target_id = _monster_actions.select_visible_target(state, monster, terrain_set, rng)
	monster.target_id = active_turn.target_id
	return not active_turn.target_id.is_empty()


func _probe_monster_advance_step(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, active_turn: CombatTurnState, rng: RealmzRng) -> BattlefieldStepResult:
	var route_targets: Array[String] = [active_turn.target_id]
	for character: CharacterState in state.party.characters():
		if _monster_actions.target_is_available(state, monster, character.id) and not route_targets.has(character.id):
			route_targets.append(character.id)
	for candidate: MonsterState in state.combat.roster.monsters():
		if _monster_actions.target_is_available(state, monster, candidate.id) and not route_targets.has(candidate.id):
			route_targets.append(candidate.id)
	var probe := _context.battlefield.probe_path_step_toward_actors(state.combat.battlefield, terrain_set, monster.id, route_targets, active_turn.movement_remaining)
	if probe.allowed:
		return probe
	var target_coordinate := state.combat.battlefield.actors.actor_position(active_turn.target_id)
	return _context.battlefield.probe_monster_step_toward(state.combat.battlefield, terrain_set, monster.id, target_coordinate, active_turn.movement_remaining, rng)


func process_monster_projectile(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _monster_actions.process_projectile(state, content, monster, definition, active_turn, rng, events)


func process_monster_retreat(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var terrain_set := _monster_actions.battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "missing-battle-terrain"}))
		active_turn.movement_remaining = 0
		return MONSTER_ATTACK_COMPLETED
	if not _monster_actions.target_is_available(state, monster, active_turn.target_id):
		# movemonster.c reads pos[-1] when a routed monster has no retained target.
		# Keep that unsafe source path explicit instead of inventing a threat target.
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "retreat-target-unresolved"}))
		return MONSTER_ATTACK_COMPLETED
	var operation_guard := 512
	while operation_guard > 0 and active_turn.movement_remaining > 0 and monster.current_health > 0:
		var origin := combat.battlefield.actors.actor_position(monster.id)
		var target_coordinate := combat.battlefield.actors.actor_position(active_turn.target_id)
		var probe := _context.battlefield.probe_monster_step_away(combat.battlefield, terrain_set, monster.id, target_coordinate, active_turn.movement_remaining, rng)
		if not probe.allowed:
			active_turn.movement_remaining = 0
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": String(probe.reason)}))
			return MONSTER_ATTACK_COMPLETED
		combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_RETREAT, monster.id, origin, probe.destination, probe.movement_cost)
		combat.pending_reaction.set_origin_hostiles(hostile_adjacent_ids(state, monster.id))
		combat.pending_reaction.set_phase(CombatReactionState.WITHDRAWAL, _context.reactions().withdrawal_hostiles(state, combat.pending_reaction))
		var reaction_result = _context.reactions().continue_pending_reaction(state, content, rng, events)
		if reaction_result == REACTION_WAITING:
			return MONSTER_ATTACK_WAITING
		if reaction_result == REACTION_DEATH_MACRO:
			return MONSTER_ATTACK_DEATH_MACRO
		if reaction_result == REACTION_MOVER_DEFEATED:
			return MONSTER_ATTACK_COMPLETED
		operation_guard -= 1
	if operation_guard == 0:
		active_turn.movement_remaining = 0
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "retreat", "reason": "monster-movement-budget-exhausted"}))
	return MONSTER_ATTACK_COMPLETED


func retreating_monster_reached_edge(state: GameState, content: RealmzContent, monster_id: String, destination: Vector2i, events: Array[DomainEvent]) -> bool:
	return _monster_actions.retreat_reached_edge(state, content, monster_id, destination, events)


func resolve_monster_attack_row(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	_monster_actions.prepare_melee_weapon(monster, definition, content)
	if not _monster_actions.target_is_available(state, monster, active_turn.target_id) or not _context.battlefield.are_adjacent(combat.battlefield, monster.id, active_turn.target_id):
		active_turn.target_id = _monster_actions.select_adjacent_target(state, monster, rng)
		monster.target_id = active_turn.target_id
	if active_turn.target_id.is_empty():
		active_turn.attack_index = _monster_actions.attack_limit(definition)
		return MONSTER_ATTACK_COMPLETED
	active_turn.attack_index += 1
	active_turn.physical_action_committed = true
	combat.actor_statuses.set_guarding(monster.id, false)
	var character_target := state.party.character_by_id(active_turn.target_id)
	if character_target != null:
		return _resolve_attack_against_character(state, content, monster, definition, attack_index, active_turn, character_target, rng, events)
	var monster_target := combat.roster.monster_by_id(active_turn.target_id)
	if monster_target == null:
		active_turn.target_id = ""
		return MONSTER_ATTACK_COMPLETED
	return _resolve_attack_against_monster(state, content, monster, definition, attack_index, active_turn, monster_target, rng, events)


func _resolve_attack_against_character(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, target: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var race := content.characters.race_by_id(target.race_id)
	var caste := content.characters.caste_by_id(target.caste_id)
	var equipment := _context.equipment.combat_equipment(target, content.items.definitions())
	var defender_luck := equipment.effective_luck if equipment.valid else target.luck
	var weapon := content.items.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
	var defender_armor := equipment.effective_armor if equipment.valid else target.armor
	var charm_bonus := 50 if state.party.conditions.is_active(ConditionRules.PARTY_CHARM_RESISTANCE) else 0
	var attack_context := MonsterAttackContext.new(weapon, state.clock.day(), false, defender_luck, state.party.conditions.is_active(ConditionRules.PARTY_DRAGON_HIDE), defender_armor)
	var resolution := _context.combat.resolve_monster_attack(monster, definition, attack_index, target, race, caste, rng, charm_bonus, attack_context, true)
	if resolution.total_damage() > 0:
		state.combat.actor_statuses.mark_attacked(target.id)
	if resolution.fumbled:
		_context.actions().events().commit_monster_fumble(monster, events)
	if resolution.special_handled:
		_context.actions().events().append_monster_special_events(events, monster.id, target.id, &"character", resolution)
		if resolution.aging != null and resolution.aging.changed_group():
			events.append(DomainEvent.new(&"character_age_changed", resolution.aging.event_payload(target, race)))
			state.combat.pending_monster_attack = PendingMonsterAttack.new(monster.id, target.id, active_turn.action, resolution.damage, resolution.chance, resolution.roll, resolution.weapon_condition_index, resolution.weapon_condition_before, resolution.weapon_condition_after, resolution.physical_feedback_sound_id)
			return MONSTER_ATTACK_WAITING
	_context.actions().events().append_monster_physical_feedback(events, resolution.physical_feedback_sound_id)
	_context.actions().events().append_monster_attack_audio(events, monster, definition, attack_index, weapon, resolution, rng)
	var attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_context.actions().events().append_physical_result_effect(attack_event, resolution.hit, weapon != null)
	events.append(attack_event)
	_context.actions().mark_character_bleeding(state, target, resolution.killed)
	remove_defeated_position(state.combat, target.id, resolution.killed)
	if resolution.killed:
		active_turn.target_id = ""
		monster.target_id = ""
	return MONSTER_ATTACK_COMPLETED


func _resolve_attack_against_monster(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, target: MonsterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var target_definition := content.combat.monster_by_id(target.definition_id)
	var weapon := content.items.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
	var attack_context := MonsterAttackContext.new(weapon, state.clock.day())
	var resolution := _context.combat.resolve_monster_attack_monster(monster, definition, attack_index, target, target_definition, rng, attack_context, true)
	if resolution.total_damage() > 0:
		state.combat.actor_statuses.mark_attacked(target.id)
	if resolution.fumbled:
		_context.actions().events().commit_monster_fumble(monster, events)
	if resolution.special_handled:
		_context.actions().events().append_monster_special_events(events, monster.id, target.id, &"monster", resolution)
	_context.actions().events().append_monster_attack_audio(events, monster, definition, attack_index, weapon, resolution, rng)
	var monster_attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_context.actions().events().append_physical_result_effect(monster_attack_event, resolution.hit, weapon != null)
	events.append(monster_attack_event)
	if resolution.killed:
		active_turn.target_id = ""
		monster.target_id = ""
		var death_macro_requested = _context.actions().events().request_monster_death_macro(target, target_definition, events)
		remove_defeated_position(state.combat, target.id, not death_macro_requested)
		if death_macro_requested:
			if active_turn.attack_index >= _monster_actions.attack_limit(definition):
				_context.rounds().advance_turn(state, content, rng, events)
			return MONSTER_ATTACK_DEATH_MACRO
	return MONSTER_ATTACK_COMPLETED


func process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	var adjacent_ids := _context.battlefield.adjacent_actor_ids(state.combat.battlefield, actor.id)
	var character_targets: Array[CharacterState] = []
	for candidate: CharacterState in state.party.characters():
		if candidate.id != actor.id and candidate.current_health > 0 and candidate.traitor != actor.traitor and adjacent_ids.has(candidate.id):
			character_targets.append(candidate)
	var monster_targets: Array[MonsterState] = []
	for candidate: MonsterState in state.combat.roster.monsters():
		if candidate.current_health > 0 and candidate.traitor != actor.traitor and adjacent_ids.has(candidate.id):
			monster_targets.append(candidate)
	var target_count := character_targets.size() + monster_targets.size()
	if target_count == 0:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": actor.id, "action": "advance", "reason": "tactical-movement-not-implemented"}))
		return false
	var target_index := rng.draw_between(0, target_count - 1, &"combat.charmed-target")
	var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
	if not equipment.valid:
		events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "reason": String(equipment.error_code), "message": equipment.error_message}))
		return false
	var active_turn := state.combat.turns.begin_active_turn()
	if active_turn == null:
		return false
	if target_index < character_targets.size():
		var character_target := character_targets[target_index]
		var target_equipment := _context.equipment.combat_equipment(character_target, content.items.definitions())
		if not target_equipment.valid:
			events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "targetId": character_target.id, "reason": String(target_equipment.error_code), "message": target_equipment.error_message}))
			return false
		active_turn.physical_action_committed = true
		var character_resolution := _context.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, state.combat.dropped_items.can_queue())
		if character_resolution.total_damage() > 0:
			state.combat.actor_statuses.mark_attacked(character_target.id)
		if character_resolution.fumbled and not _context.actions().events().commit_character_fumble(state, actor, equipment, events):
			events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": actor.id, "reason": "invalid-fumble-state"}))
			return false
		var character_event = _context.actions().events().character_attack_event(actor.id, character_target.id, &"character", character_resolution, equipment.melee_weapon != null)
		_context.actions().events().append_character_attack_audio(events, actor, equipment, character_resolution, &"character")
		character_event.payload["automatic"] = true
		events.append(character_event)
		_context.actions().mark_character_bleeding(state, character_target, character_resolution.killed)
		remove_defeated_position(state.combat, character_target.id, character_resolution.killed)
		return false
	var monster_target := monster_targets[target_index - character_targets.size()]
	var target_definition := content.combat.monster_by_id(monster_target.definition_id)
	active_turn.physical_action_committed = true
	var resolution := _context.combat.resolve_character_attack(actor, equipment, monster_target, target_definition, rng, state.clock.day(), false, true, state.combat.dropped_items.can_queue())
	if resolution.total_damage() > 0:
		state.combat.actor_statuses.mark_attacked(monster_target.id)
	if resolution.fumbled and not _context.actions().events().commit_character_fumble(state, actor, equipment, events):
		events.append(DomainEvent.new(&"combat_fumble_failed", {"actorId": actor.id, "reason": "invalid-fumble-state"}))
		return false
	var event = _context.actions().events().character_attack_event(actor.id, monster_target.id, &"monster", resolution, equipment.melee_weapon != null)
	_context.actions().events().append_character_attack_audio(events, actor, equipment, resolution, &"monster")
	event.payload["automatic"] = true
	events.append(event)
	var death_macro_requested = resolution.killed and _context.actions().events().request_monster_death_macro(monster_target, target_definition, events)
	remove_defeated_position(state.combat, monster_target.id, resolution.killed and not death_macro_requested)
	return death_macro_requested


func hostile_adjacent_ids(state: GameState, actor_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	return _occupancy.hostile_adjacent_ids(state, actor_id, anchor_override)


func hostile_contact_target_id(state: GameState, actor_id: String, destination_or_target: Variant) -> String:
	return _occupancy.hostile_contact_target_id(state, actor_id, destination_or_target)


static func remove_defeated_position(combat: CombatState, actor_id: String, defeated: bool) -> void:
	CombatOccupancyRules.remove_defeated_position(combat, actor_id, defeated)


static func remove_all_defeated_positions(state: GameState) -> void:
	CombatOccupancyRules.remove_all_defeated_positions(state)
