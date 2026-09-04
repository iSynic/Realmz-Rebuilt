## Coordinates automatic party and monster activations without owning combat rules.
class_name CombatFlowAutomation
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
var _ai_scoring: RefCounted
var _monster_actions: CombatMonsterActions


func _init(context: CombatContext) -> void:
	_context = context
	_ai_scoring = CombatAiScoring.new(context)
	_monster_actions = CombatMonsterActions.new(context)

func monster_actions() -> CombatMonsterActions:
	return _monster_actions

func run_auto_turn(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	var unavailable := _auto_unavailable(state, content, actor_id, rng)
	if unavailable != null:
		return unavailable
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var result := _run_auto_turn_unchecked(state, content, actor_id, rng)
	return _commit_or_rollback(state, rng, state_checkpoint, rng_checkpoint, result, "Automatic combat")


func run_auto_activation_chain(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	var unavailable := _auto_unavailable(state, content, actor_id, rng)
	if unavailable != null:
		return unavailable
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var result := _run_auto_turn_unchecked(state, content, actor_id, rng)
	return _commit_or_rollback(state, rng, state_checkpoint, rng_checkpoint, result, "Auto Turn")


func _run_auto_turn_unchecked(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	var actor := state.party.character_by_id(actor_id)
	# Action scoring must see this activation's authoritative movement and attack
	# allowances. CharacterState retains the spent values from its prior turn
	# until the active-turn record is prepared.
	_context.actions().prepare_character_turn(state.combat, actor)
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_auto_started", {"actorId": actor.id, "persistent": state.combat_auto_enabled(actor.id), "source": "classic"})]
	var visited_anchors: Array[Vector2i] = [state.combat.battlefield.actor_position(actor.id)]
	var starting_round := state.combat.round_number
	var operation_count := 0
	var previous_processing = _context.processing_auto
	_context.processing_auto = true
	while operation_count < MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed and state.combat.active_actor_id() == actor_id and state.combat.round_number == starting_round:
		operation_count += 1
		var choice: Dictionary = _ai_scoring.choose_party_action(state, content, actor, rng)
		var chosen_action := StringName(choice.get("action", &"defend"))
		var result := _execute_auto_choice(state, content, actor, choice, rng, visited_anchors)
		if result == null or not result.ok:
			# A scored spell or attack can become invalid when an earlier operation in
			# the same activation changes occupancy or resources. Continue tactical
			# pursuit before falling back to Castle's stationary defend action.
			if chosen_action != &"move" and actor.movement > 0:
				result = auto_move_toward_target(state, content, actor, rng, visited_anchors)
		if result == null or not result.ok:
			result = _context.actions().submit_action(state, content, actor.id, &"defend", "", rng)
		if result == null or not result.ok:
			_context.processing_auto = previous_processing
			return CombatFlowResult.failed(&"combat_auto_failed", "Automatic combat could not choose a legal source-backed action.")
		events.append_array(result.events)
		if state.combat != null and state.combat.battlefield.has_actor(actor.id):
			var current_anchor := state.combat.battlefield.actor_position(actor.id)
			if not visited_anchors.has(current_anchor):
				visited_anchors.append(current_anchor)
		if result.completed or _events_include(result.events, &"monster_death_macro_requested") or state.combat.pending_monster_attack != null:
			break
	_context.processing_auto = previous_processing
	if operation_count >= MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed and state.combat.active_actor_id() == actor_id and state.combat.round_number == starting_round:
		return CombatFlowResult.failed(&"combat_auto_operation_limit", "Automatic combat exceeded its 256-operation safety limit without committing a partial activation.")
	events.append(DomainEvent.new(&"combat_auto_completed", {"actorId": actor.id, "operations": operation_count, "source": "classic"}))
	return CombatFlowResult.succeeded(events, state.combat == null or state.combat.completed)


func _execute_auto_choice(state: GameState, content: RealmzContent, actor: CharacterState, choice: Dictionary, rng: RealmzRng, visited_anchors: Array[Vector2i]) -> CombatFlowResult:
	var action := StringName(choice.get("action", &"defend"))
	if action == &"cast_spell":
		var target_ids: Array[String] = []
		target_ids.assign(choice.get("targetIds", []))
		var target_coordinates: Array[Vector2i] = []
		target_coordinates.assign(choice.get("targetCoordinates", []))
		return _context.magic_flow().cast_spell(state, content, actor.id, String(choice.get("targetId", "")), String(choice["spellId"]), int(choice["power"]), rng, choice.get("coordinate", INVALID_COORDINATE), int(choice.get("rotation", 0)), target_ids, target_coordinates)
	if action == &"move":
		return auto_move_toward_target(state, content, actor, rng, visited_anchors)
	return _context.actions().submit_action(state, content, actor.id, action, String(choice.get("targetId", "")), rng)


func run_persistent_auto_characters(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.succeeded([])
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var result := _run_persistent_auto_unchecked(state, content, rng)
	return _commit_or_rollback(state, rng, state_checkpoint, rng_checkpoint, result, "Persistent Auto")


func _run_persistent_auto_unchecked(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	if state.combat == null or state.combat.completed:
		return CombatFlowResult.succeeded([], true)
	var actor_id := state.combat.active_actor_id()
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.traitor or not state.combat_auto_enabled(actor_id):
		return CombatFlowResult.succeeded([])
	return _run_auto_turn_unchecked(state, content, actor_id, rng)


func _auto_unavailable(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.failed(&"combat_auto_unavailable", "No active battle can resolve an automatic turn.")
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor or state.combat.active_actor_id() != actor_id:
		return CombatFlowResult.failed(&"combat_auto_unavailable", "Only the active loyal character can use Auto Turn.")
	return null


func _commit_or_rollback(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, result: CombatFlowResult, operation_name: String) -> CombatFlowResult:
	if result.ok:
		return result
	if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"combat_auto_rollback_failed", "%s failed and could not restore its deterministic transaction boundary." % operation_name)
	return result


func auto_move_toward_target(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, visited_anchors: Array[Vector2i] = []) -> CombatFlowResult:
	var combat := state.combat
	_context.actions().prepare_character_turn(combat, actor)
	if actor.movement <= 0:
		return CombatFlowResult.failed(&"combat_auto_no_movement", "The automatic character cannot move toward a target.")
	var candidates: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.id != actor.id and character.current_health > 0 and character.traitor != actor.traitor and combat.battlefield.has_actor(character.id):
			candidates.append(character.id)
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor != actor.traitor and combat.battlefield.has_actor(monster.id):
			candidates.append(monster.id)
	if candidates.is_empty():
		return CombatFlowResult.failed(&"combat_auto_no_target", "No opposed battlefield combatant remains.")
	var target_id := combat.active_turn.target_id
	if not candidates.has(target_id):
		target_id = candidates[rng.draw_between(0, candidates.size() - 1, StringName("combat.auto.%s.target" % actor.id))]
		combat.active_turn.target_id = target_id
	var origin := combat.battlefield.actor_position(actor.id)
	var terrain_set := _monster_actions.battle_terrain_set(content, combat.battlefield)
	var swappable_ids: Array[String] = []
	if combat.battlefield.actor_size(actor.id) == 0:
		for character: CharacterState in state.party.characters():
			if character.id != actor.id and character.current_health > 0 and character.traitor == actor.traitor and combat.battlefield.has_actor(character.id) and combat.battlefield.actor_size(character.id) == 0:
				swappable_ids.append(character.id)
		for monster: MonsterState in combat.monsters():
			if monster.current_health > 0 and monster.traitor == actor.traitor and combat.battlefield.has_actor(monster.id) and combat.battlefield.actor_size(monster.id) == 0:
				swappable_ids.append(monster.id)
	var path_probe := _direct_auto_swap_probe(combat.battlefield, actor.id, target_id, actor.movement, swappable_ids, visited_anchors)
	if path_probe == null:
		path_probe = _context.battlefield.probe_path_step_toward_actors(combat.battlefield, terrain_set, actor.id, candidates, actor.movement, swappable_ids, visited_anchors)
	if path_probe.allowed:
		return _context.reactions().move_character(state, content, actor.id, path_probe.destination, rng)
	if path_probe.reason != &"path_not_found":
		return CombatFlowResult.failed(&"combat_auto_route_satisfied", "The automatic character has no productive pursuit step.")
	for retry: int in 20:
		var shifted := Vector2i(rng.draw(3, StringName("combat.auto.%s.shift.%d.x" % [actor.id, retry])) - 2, rng.draw(3, StringName("combat.auto.%s.shift.%d.y" % [actor.id, retry])) - 2)
		if shifted == Vector2i.ZERO or visited_anchors.has(origin + shifted):
			continue
		var shifted_result = _context.reactions().move_character(state, content, actor.id, origin + shifted, rng)
		if shifted_result.ok:
			return shifted_result
	return CombatFlowResult.failed(&"combat_auto_blocked", "The automatic character exhausted Castle's bounded movement retries.")


static func _direct_auto_swap_probe(battlefield: BattlefieldState, actor_id: String, target_id: String, movement: int, swappable_ids: Array[String], visited_anchors: Array[Vector2i]) -> BattlefieldStepResult:
	if battlefield == null or movement < 5 or not battlefield.has_actor(actor_id) or not battlefield.has_actor(target_id):
		return null
	var origin := battlefield.actor_position(actor_id)
	var target := battlefield.actor_position(target_id)
	var destination := origin + Vector2i(signi(target.x - origin.x), signi(target.y - origin.y))
	if visited_anchors.has(destination) or not swappable_ids.has(battlefield.actor_at(destination, actor_id)):
		return null
	return BattlefieldStepResult.permitted(destination, 5)


static func _events_include(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false


func process_monster_turns(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	var combat := state.combat
	if combat == null or not combat.pending_spell_death_macro_id().is_empty():
		return
	# The order may grow while this loop is active when a monster casts a
	# multi-summon or a death macro adds combatants. Bound the scan by the
	# authoritative actor capacities instead of the order's stale entry count.
	var guard := MAX_MONSTERS + state.party.characters().size()
	while guard > 0 and not combat.completed and combat.pending_spell_death_macro_id().is_empty():
		var actor_id := combat.active_actor_id()
		var monster := combat.monster_by_id(actor_id)
		if monster == null:
			var charmed_actor := state.party.character_by_id(actor_id)
			if charmed_actor != null and (combat.battlefield == null or not combat.battlefield.has_actor(charmed_actor.id)):
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
		if combat.active_turn == null:
			combat.set_guarding(monster.id, true)
		if monster.conditions.is_active(ConditionRules.HELPLESS):
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "incapacitated"}))
			_context.rounds().advance_turn(state, content, rng, events)
			guard -= 1
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": "unavailable_definition"}))
			_context.rounds().advance_turn(state, content, rng, events)
			guard -= 1
			continue
		var active_turn := combat.begin_active_turn()
		if active_turn.movement_remaining < 0:
			active_turn.movement_remaining = _monster_actions.movement_allowance(monster, definition)
		if active_turn.target_id.is_empty() and active_turn.attack_index == 0:
			active_turn.target_id = monster.target_id
		if active_turn.action.is_empty():
			active_turn.action = _ai_scoring.choose_monster_action(state, content, monster, definition, rng)
		var attack_result := MONSTER_ATTACK_COMPLETED
		if active_turn.action == &"advance":
			if monster.conditions.is_active(ConditionRules.SPEEDY):
				events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "monster-speedy-cadence-unresolved"}))
			elif monster.conditions.value(ConditionRules.TANGLED) < 0:
				events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "permanent-tangle-movement-unresolved"}))
			else:
				attack_result = process_monster_advance(state, content, monster, definition, active_turn, rng, events)
				if attack_result != MONSTER_ATTACK_COMPLETED:
					return
				if monster_can_retry_cast(state, monster, definition, active_turn):
					attack_result = process_monster_cast(state, content, monster, definition, active_turn, rng, events)
					if attack_result != MONSTER_ATTACK_COMPLETED:
						return
		elif active_turn.action == &"missile":
			attack_result = process_monster_projectile(state, content, monster, definition, active_turn, rng, events)
			if attack_result == MONSTER_ATTACK_FALLBACK:
				active_turn.action = _ai_scoring.choose_monster_action(state, content, monster, definition, rng, false)
				if active_turn.action == &"cast":
					attack_result = process_monster_cast(state, content, monster, definition, active_turn, rng, events)
					if attack_result == MONSTER_ATTACK_FALLBACK:
						active_turn.action = &"advance"
						attack_result = process_monster_advance(state, content, monster, definition, active_turn, rng, events)
						if attack_result == MONSTER_ATTACK_COMPLETED and monster_can_retry_cast(state, monster, definition, active_turn):
							attack_result = process_monster_cast(state, content, monster, definition, active_turn, rng, events)
				else:
					attack_result = process_monster_advance(state, content, monster, definition, active_turn, rng, events)
					if attack_result == MONSTER_ATTACK_COMPLETED and monster_can_retry_cast(state, monster, definition, active_turn):
						attack_result = process_monster_cast(state, content, monster, definition, active_turn, rng, events)
			if attack_result != MONSTER_ATTACK_COMPLETED:
				return
		elif active_turn.action == &"cast":
			attack_result = process_monster_cast(state, content, monster, definition, active_turn, rng, events)
			if attack_result == MONSTER_ATTACK_FALLBACK:
				active_turn.action = &"advance"
				attack_result = process_monster_advance(state, content, monster, definition, active_turn, rng, events)
				if attack_result == MONSTER_ATTACK_COMPLETED and monster_can_retry_cast(state, monster, definition, active_turn):
					attack_result = process_monster_cast(state, content, monster, definition, active_turn, rng, events)
			if attack_result != MONSTER_ATTACK_COMPLETED:
				return
		elif active_turn.action == &"retreat":
			attack_result = process_monster_retreat(state, content, monster, definition, active_turn, rng, events)
			if attack_result != MONSTER_ATTACK_COMPLETED:
				return
		else:
			events.append(DomainEvent.new(&"combat_monster_action", {"actorId": monster.id, "action": String(active_turn.action)}))
		_context.rounds().advance_turn(state, content, rng, events)
		if _context.rounds().finish_if_resolved(state, content, events):
			break
		guard -= 1


func process_monster_cast(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	active_turn.monster_cast_attempt_count += 1
	if state.monster_spellcasting_blocked or state.combat.was_attacked(monster.id) or definition.magic_attack_count <= 0:
		return MONSTER_ATTACK_FALLBACK
	for condition: int in [ConditionRules.STUPID, ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS]:
		if monster.conditions.is_active(condition):
			return MONSTER_ATTACK_FALLBACK
	var did_cast := active_turn.spell_cast_count > 0
	while active_turn.spell_cast_count < definition.magic_attack_count:
		var plan: Dictionary = _ai_scoring.best_monster_spell_plan(state, content, monster, definition)
		if plan.is_empty():
			break
		var spell := content.spell_by_id(String(plan["spellId"]))
		var range_power := int(plan["power"])
		var cost_power := range_power
		var selected_targets: Array[SpellTargetSelection] = []
		var planned_target_ids: Array[String] = []
		var area_center := INVALID_COORDINATE
		var area_rotation := 0
		var area_shape := 0
		var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
		if summon_spell:
			var target_coordinates: Array[Vector2i] = []
			target_coordinates.assign(plan.get("targetCoordinates", []))
			if target_coordinates.is_empty():
				break
			state.combat.set_guarding(monster.id, false)
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
		elif spell.target_type in [3, 4]:
			area_center = plan.get("coordinate", INVALID_COORDINATE)
			area_rotation = int(plan.get("rotation", 0))
			area_shape = _context.spell_areas.shape_for(spell, cost_power, area_rotation)
			selected_targets = _monster_area_spell_selections(state, content, area_center, area_shape)
		else:
			if spell.target_type == 5:
				area_center = state.combat.battlefield.actor_position(monster.id)
				area_shape = 1
			for target_id: String in plan["targetIds"]:
				planned_target_ids.append(target_id)
			if spell.target_type == 6:
				planned_target_ids = _context.magic_flow().ray_spell_actor_ids(state, content, monster.id, planned_target_ids[0], spell)
			for target_id: String in planned_target_ids:
				var selection := _monster_spell_target_selection(state, content, target_id)
				if selection != null:
					selected_targets.append(selection)
		if selected_targets.is_empty():
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		var cast_level := spell.classic_tier()
		if cast_level < 0 or cast_level > 6:
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": spell.id, "reason": "invalid-classic-spell-tier"}))
			if did_cast:
				break
			return MONSTER_ATTACK_COMPLETED
		state.combat.set_guarding(monster.id, false)
		active_turn.movement_remaining = 0
		var resolutions: GroupSpellResolution
		var persistent_field: RefCounted = null
		var repeated_fields: Array[RefCounted] = []
		if ClassicSpellCapabilityCatalog.is_combat_persistent_field_spell(spell):
			persistent_field = _context.fields().queue_persistent_field(state.combat, monster.id, spell, cost_power, cast_level, rng, area_center, area_rotation, area_shape)
			if persistent_field == null:
				events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "spellId": spell.id, "reason": "persistent-field-queue-limit"}))
				return MONSTER_ATTACK_COMPLETED if did_cast else MONSTER_ATTACK_FALLBACK
		if ClassicSpellCapabilityCatalog.is_combat_single_actor_field_spell(spell):
			var actor_field: RefCounted = _context.fields().queue_single_actor_field(state, monster.id, planned_target_ids[0], spell, cost_power, cast_level, rng)
			if actor_field != null: repeated_fields.append(actor_field)
		if spell.target_type in [3, 4]:
			resolutions = _context.magic.resolve_monster_group_spell(monster, definition, selected_targets, spell, cost_power, cast_level, rng, true, true, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
		elif spell.target_type in [9, 10, 12]:
			resolutions = _context.magic.resolve_monster_group_spell(monster, definition, selected_targets, spell, cost_power, cast_level, rng, false, true, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
		elif spell.target_type == 0:
			resolutions = _context.magic.resolve_monster_repeated_spell(monster, definition, selected_targets, spell, cost_power, cast_level, rng, _context.fields().repeated_field_callback(state, spell, monster.id, planned_target_ids, cost_power, cast_level, rng, repeated_fields))
		elif spell.target_type == 6:
			resolutions = _context.magic.resolve_monster_ray_spell(monster, definition, selected_targets, spell, cost_power, cast_level, rng)
		else:
			resolutions = _context.magic.resolve_monster_targeted_spell(monster, definition, selected_targets[0], spell, cost_power, cast_level, rng, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
		if resolutions == null or not resolutions.cast:
			if did_cast:
				break
			return MONSTER_ATTACK_FALLBACK
		active_turn.spell_cast_count += 1
		did_cast = true
		if persistent_field != null:
			repeated_fields.append(persistent_field)
		_context.fields().append_created_events(events, repeated_fields, "classic-monster")
		CombatSpellEventBuilder.append_sound(events, spell.sound_start, "classic-monster-spell-start")
		CombatSpellEventBuilder.append_cast(events, monster.id, spell, resolutions, area_center, area_shape, "classic-monster")
		_append_monster_spell_resolution_events(state, content, monster, spell, resolutions, cost_power, range_power, cast_level, area_center, area_shape, events)
	return _finish_monster_cast(state, content, monster, did_cast, events)


func _append_monster_spell_resolution_events(state: GameState, content: RealmzContent, monster: MonsterState, spell: SpellDefinition, resolutions: GroupSpellResolution, cost_power: int, range_power: int, cast_level: int, area_center: Vector2i, area_shape: int, events: Array[DomainEvent]) -> void:
	for index: int in resolutions.resolutions.size():
		var resolution := resolutions.resolutions[index]
		var resolved_target_id := resolutions.target_ids[index]
		var selected_target_id := resolutions.selected_target_ids[index]
		var target_kind := resolutions.target_kinds[index]
		var reflected := resolutions.reflected_targets[index]
		if resolution.damage > 0 or (resolution.damage < 0 and target_kind == &"monster"):
			state.combat.mark_attacked(resolved_target_id)
		CombatSpellEventBuilder.append_projectile(events, monster.id, resolved_target_id, spell, "classic-monster")
		CombatSpellEventBuilder.append_sound(events, spell.sound_end, "classic-monster-spell-result")
		var payload := {"actorId": monster.id, "targetId": resolved_target_id, "selectedTargetId": selected_target_id, "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": cost_power, "rangePower": range_power, "classicTier": cast_level, "reflected": reflected, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": "classic-monster", "detectedMagicItemCount": resolution.detected_magic_item_count}
		if resolution.spell_point_delta != 0 or ClassicSpellCapabilityCatalog.is_combat_spell_point_restore_spell(spell) or ClassicSpellCapabilityCatalog.is_combat_spell_point_drain_spell(spell):
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
	var defeated_monster := state.combat.monster_by_id(target_id)
	var defeated_definition := content.monster_by_id(defeated_monster.definition_id) if defeated_monster != null else null
	var queued = _context.actions().events().queue_spell_death_macro(state.combat, defeated_monster, defeated_definition)
	if not queued and defeated_definition != null and defeated_definition.death_macro > 0:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": caster.id, "action": "cast", "targetId": target_id, "reason": "spell-death-macro-queue-limit"}))
	# Castle continues after reflection kills the caster, so retain its anchor until
	# the spell sequence and queued death macros have both finished.
	remove_defeated_position(state.combat, target_id, not queued and target_id != caster.id)


func _finish_monster_cast(state: GameState, content: RealmzContent, monster: MonsterState, did_cast: bool, events: Array[DomainEvent]) -> int:
	if not state.combat.pending_spell_death_macro_id().is_empty():
		if not state.combat.begin_spell_death_macro_sequence(monster.id, true) or not _context.actions().events().request_next_spell_death_macro(state.combat, content, events):
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "cast", "reason": "invalid-spell-death-macro-queue"}))
			return MONSTER_ATTACK_COMPLETED
		return MONSTER_ATTACK_DEATH_MACRO
	if monster.current_health <= 0:
		remove_defeated_position(state.combat, monster.id, true)
	return MONSTER_ATTACK_COMPLETED if did_cast else MONSTER_ATTACK_FALLBACK


func _monster_area_spell_selections(state: GameState, content: RealmzContent, center: Vector2i, shape: int) -> Array[SpellTargetSelection]:
	var selected_ids: Dictionary = {}
	for offset: Vector2i in _context.spell_areas.pattern(shape):
		var actor_id := state.combat.battlefield.actor_at(center + offset)
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var result: Array[SpellTargetSelection] = []
	for character: CharacterState in state.party.characters():
		if selected_ids.has(character.id) and character.current_health > 0 and state.combat.battlefield.has_actor(character.id):
			result.append(SpellTargetSelection.for_character(character))
	for monster: MonsterState in state.combat.monsters():
		if not selected_ids.has(monster.id) or monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id) or monster.magic_resistance > 100:
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition != null:
			result.append(SpellTargetSelection.for_monster(monster, definition))
	return result


static func _monster_spell_target_selection(state: GameState, content: RealmzContent, target_id: String) -> SpellTargetSelection:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return SpellTargetSelection.for_character(character)
	var monster := state.combat.monster_by_id(target_id)
	var definition := content.monster_by_id(monster.definition_id) if monster != null else null
	return SpellTargetSelection.for_monster(monster, definition) if definition != null else null


static func monster_can_retry_cast(state: GameState, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState) -> bool:
	return definition.cast_percent != 0 and not active_turn.physical_action_committed and active_turn.spell_cast_count == 0 and active_turn.monster_cast_attempt_count < 2 and monster.current_health > 0 and not state.combat.was_attacked(monster.id) and not state.monster_spellcasting_blocked


static func monster_spell_unavailable_reason(spell: SpellDefinition) -> String:
	if ClassicSpellCapabilityCatalog.combat_monster_disposition(spell) != ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE:
		return ClassicSpellCapabilityCatalog.unsupported_reason(spell, &"combat-monster")
	var healing_spell := ClassicSpellCapabilityCatalog.is_combat_healing_spell(spell)
	var condition_cure := ClassicSpellCapabilityCatalog.is_combat_condition_cure_spell(spell)
	var condition_effect := ClassicSpellCapabilityCatalog.is_combat_condition_effect_spell(spell)
	var spell_point_restore := ClassicSpellCapabilityCatalog.is_combat_spell_point_restore_spell(spell)
	var destroy_magic := ClassicSpellCapabilityCatalog.is_combat_destroy_magic_spell(spell)
	var charm_spell := ClassicSpellCapabilityCatalog.is_combat_charm_spell(spell)
	if spell.cannot == 4 and not healing_spell and not condition_cure and not condition_effect and not spell_point_restore and not destroy_magic and not charm_spell:
		return "monster-spell-friendly-target-unresolved"
	return ""


static func is_source_backed_combat_healing_spell(spell: SpellDefinition) -> bool:
	return ClassicSpellCapabilityCatalog.is_combat_healing_spell(spell)


func process_monster_advance(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var terrain_set := _monster_actions.battle_terrain_set(content, combat.battlefield)
	if terrain_set == null:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "missing-battle-terrain"}))
		active_turn.movement_remaining = 0
		return MONSTER_ATTACK_COMPLETED
	var contact_origin := combat.battlefield.actor_position(monster.id)
	combat.pending_reaction = CombatReactionState.new(CombatReactionState.MONSTER_CONTACT, monster.id, contact_origin, contact_origin, 0)
	combat.pending_reaction.set_phase(CombatReactionState.GUARD_AFTER, _context.reactions().guarding_hostiles(state, monster.id))
	var contact_result = _context.reactions().continue_pending_reaction(state, content, rng, events)
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
		if _monster_actions.target_is_available(state, monster, active_turn.target_id) and not _context.battlefield.has_line_of_sight(combat.battlefield, terrain_set, monster.id, active_turn.target_id):
			active_turn.target_id = _monster_actions.scan_visible_target(state, monster, terrain_set)
			monster.target_id = active_turn.target_id
		elif not _monster_actions.target_is_available(state, monster, active_turn.target_id):
			active_turn.target_id = _monster_actions.select_visible_target(state, monster, terrain_set, rng)
			monster.target_id = active_turn.target_id
		if active_turn.target_id.is_empty():
			active_turn.movement_remaining = 0
			events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": monster.id, "action": "advance", "reason": "no-visible-target"}))
			return MONSTER_ATTACK_COMPLETED
		var origin := combat.battlefield.actor_position(monster.id)
		var route_targets: Array[String] = [active_turn.target_id]
		for character: CharacterState in state.party.characters():
			if _monster_actions.target_is_available(state, monster, character.id) and not route_targets.has(character.id): route_targets.append(character.id)
		for candidate: MonsterState in combat.monsters():
			if _monster_actions.target_is_available(state, monster, candidate.id) and not route_targets.has(candidate.id): route_targets.append(candidate.id)
		var probe := _context.battlefield.probe_path_step_toward_actors(combat.battlefield, terrain_set, monster.id, route_targets, active_turn.movement_remaining)
		if not probe.allowed:
			probe = _context.battlefield.probe_monster_step_toward(combat.battlefield, terrain_set, monster.id, combat.battlefield.actor_position(active_turn.target_id), active_turn.movement_remaining, rng)
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
		var origin := combat.battlefield.actor_position(monster.id)
		var target_coordinate := combat.battlefield.actor_position(active_turn.target_id)
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
	combat.set_guarding(monster.id, false)
	var character_target := state.party.character_by_id(active_turn.target_id)
	if character_target != null:
		var race := content.race_by_id(character_target.race_id)
		var caste := content.caste_by_id(character_target.caste_id)
		var charm_bonus := 50 if state.party.conditions.is_active(ConditionRules.PARTY_CHARM_RESISTANCE) else 0
		var defender_equipment := _context.inventory.combat_equipment(character_target, content.item_definitions())
		var defender_luck := defender_equipment.effective_luck if defender_equipment.valid else character_target.luck
		var attack_weapon := content.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
		var defender_armor := defender_equipment.effective_armor if defender_equipment.valid else character_target.armor
		var monster_attack_context := MonsterAttackContext.new(attack_weapon, state.clock.day(), false, defender_luck, state.party.conditions.is_active(ConditionRules.PARTY_DRAGON_HIDE), defender_armor)
		var monster_resolution := _context.combat.resolve_monster_attack(monster, definition, attack_index, character_target, race, caste, rng, charm_bonus, monster_attack_context, true)
		if monster_resolution.total_damage() > 0:
			combat.mark_attacked(character_target.id)
		if monster_resolution.fumbled:
			_context.actions().events().commit_monster_fumble(monster, events)
		var age_update_requested := false
		if monster_resolution.special_handled:
			_context.actions().events().append_monster_special_events(events, monster.id, character_target.id, &"character", monster_resolution)
			if monster_resolution.aging != null and monster_resolution.aging.changed_group():
				events.append(DomainEvent.new(&"character_age_changed", monster_resolution.aging.event_payload(character_target, race)))
				age_update_requested = true
		if age_update_requested:
			combat.pending_monster_attack = PendingMonsterAttack.new(monster.id, character_target.id, active_turn.action, monster_resolution.damage, monster_resolution.chance, monster_resolution.roll, monster_resolution.weapon_condition_index, monster_resolution.weapon_condition_before, monster_resolution.weapon_condition_after, monster_resolution.physical_feedback_sound_id)
			return MONSTER_ATTACK_WAITING
		_context.actions().events().append_monster_physical_feedback(events, monster_resolution.physical_feedback_sound_id)
		_context.actions().events().append_monster_attack_audio(events, monster, definition, attack_index, attack_weapon, monster_resolution, rng)
		var character_attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": character_target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": monster_resolution.hit, "damage": monster_resolution.total_damage(), "defeated": monster_resolution.killed, "chance": monster_resolution.chance, "roll": monster_resolution.roll})
		_context.actions().events().append_physical_result_effect(character_attack_event, monster_resolution.hit, attack_weapon != null)
		events.append(character_attack_event)
		_context.actions().mark_character_bleeding(state, character_target, monster_resolution.killed)
		remove_defeated_position(combat, character_target.id, monster_resolution.killed)
		if monster_resolution.killed:
			active_turn.target_id = ""
			monster.target_id = ""
		return MONSTER_ATTACK_COMPLETED
	var monster_target := combat.monster_by_id(active_turn.target_id)
	if monster_target == null:
		active_turn.target_id = ""
		return MONSTER_ATTACK_COMPLETED
	var target_definition := content.monster_by_id(monster_target.definition_id)
	var weapon := content.item_by_id(monster.weapon_id) if not monster.weapon_id.is_empty() else null
	var attack_context := MonsterAttackContext.new(weapon, state.clock.day())
	var resolution := _context.combat.resolve_monster_attack_monster(monster, definition, attack_index, monster_target, target_definition, rng, attack_context, true)
	if resolution.total_damage() > 0:
		combat.mark_attacked(monster_target.id)
	if resolution.fumbled:
		_context.actions().events().commit_monster_fumble(monster, events)
	if resolution.special_handled:
		_context.actions().events().append_monster_special_events(events, monster.id, monster_target.id, &"monster", resolution)
	_context.actions().events().append_monster_attack_audio(events, monster, definition, attack_index, weapon, resolution, rng)
	var monster_attack_event := DomainEvent.new(&"combat_attack_resolved", {"actorId": monster.id, "targetId": monster_target.id, "action": String(active_turn.action), "attackIndex": attack_index, "hit": resolution.hit, "damage": resolution.total_damage(), "defeated": resolution.killed, "chance": resolution.chance, "roll": resolution.roll})
	_context.actions().events().append_physical_result_effect(monster_attack_event, resolution.hit, weapon != null)
	events.append(monster_attack_event)
	if resolution.killed:
		active_turn.target_id = ""
		monster.target_id = ""
		var death_macro_requested = _context.actions().events().request_monster_death_macro(monster_target, target_definition, events)
		remove_defeated_position(combat, monster_target.id, not death_macro_requested)
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
	for candidate: MonsterState in state.combat.monsters():
		if candidate.current_health > 0 and candidate.traitor != actor.traitor and adjacent_ids.has(candidate.id):
			monster_targets.append(candidate)
	var target_count := character_targets.size() + monster_targets.size()
	if target_count == 0:
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": actor.id, "action": "advance", "reason": "tactical-movement-not-implemented"}))
		return false
	var target_index := rng.draw_between(0, target_count - 1, &"combat.charmed-target")
	var equipment := _context.inventory.combat_equipment(actor, content.item_definitions())
	if not equipment.valid:
		events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "reason": String(equipment.error_code), "message": equipment.error_message}))
		return false
	var active_turn := state.combat.begin_active_turn()
	if active_turn == null:
		return false
	if target_index < character_targets.size():
		var character_target := character_targets[target_index]
		var target_equipment := _context.inventory.combat_equipment(character_target, content.item_definitions())
		if not target_equipment.valid:
			events.append(DomainEvent.new(&"combat_attack_blocked", {"actorId": actor.id, "targetId": character_target.id, "reason": String(target_equipment.error_code), "message": target_equipment.error_message}))
			return false
		active_turn.physical_action_committed = true
		var character_resolution := _context.combat.resolve_character_attack_character(actor, equipment, character_target, target_equipment, rng, false, true, state.combat.can_queue_fumbled_item())
		if character_resolution.total_damage() > 0:
			state.combat.mark_attacked(character_target.id)
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
	var target_definition := content.monster_by_id(monster_target.definition_id)
	active_turn.physical_action_committed = true
	var resolution := _context.combat.resolve_character_attack(actor, equipment, monster_target, target_definition, rng, state.clock.day(), false, true, state.combat.can_queue_fumbled_item())
	if resolution.total_damage() > 0:
		state.combat.mark_attacked(monster_target.id)
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
	var result: Array[String] = []
	if state == null or state.combat == null or state.combat.battlefield == null:
		return result
	var actor_traitor := false
	var character := state.party.character_by_id(actor_id)
	if character != null:
		actor_traitor = character.traitor
	else:
		var monster := state.combat.monster_by_id(actor_id)
		if monster == null:
			return result
		actor_traitor = monster.traitor
	var adjacent_ids := _context.battlefield.adjacent_actor_ids(state.combat.battlefield, actor_id, anchor_override)
	# Castle scans numeric combat slots: party members first, then monsters in
	# authored runtime order. Stable IDs must not accidentally redefine reactions.
	for candidate_character: CharacterState in state.party.characters():
		if adjacent_ids.has(candidate_character.id) and candidate_character.current_health > 0 and candidate_character.traitor != actor_traitor:
			result.append(candidate_character.id)
	for candidate_monster: MonsterState in state.combat.monsters():
		if adjacent_ids.has(candidate_monster.id) and candidate_monster.current_health > 0 and candidate_monster.traitor != actor_traitor:
			result.append(candidate_monster.id)
	return result


func hostile_contact_target_id(state: GameState, actor_id: String, destination_or_target: Variant) -> String:
	if state == null or state.combat == null or state.combat.battlefield == null:
		return ""
	var candidate_id := ""
	if destination_or_target is String:
		candidate_id = destination_or_target
	elif destination_or_target is Vector2i:
		candidate_id = state.combat.battlefield.actor_at(destination_or_target, actor_id)
	if candidate_id.is_empty():
		return ""
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0:
		return ""
	var monster := state.combat.monster_by_id(candidate_id)
	if monster != null:
		return candidate_id if monster.current_health > 0 and monster.traitor != actor.traitor else ""
	var character := state.party.character_by_id(candidate_id)
	return candidate_id if character != null and character.current_health > 0 and character.traitor != actor.traitor else ""


static func remove_defeated_position(combat: CombatState, actor_id: String, defeated: bool) -> void:
	if not defeated or combat == null or combat.battlefield == null:
		return
	if combat.monster_by_id(actor_id) != null:
		combat.battlefield.remove_monster(actor_id)
	else:
		combat.battlefield.remove_character(actor_id)


static func remove_all_defeated_positions(state: GameState) -> void:
	if state == null or state.combat == null or state.combat.battlefield == null:
		return
	for monster: MonsterState in state.combat.monsters():
		remove_defeated_position(state.combat, monster.id, monster.current_health <= 0)
	for character: CharacterState in state.party.characters():
		remove_defeated_position(state.combat, character.id, character.current_health <= 0)
