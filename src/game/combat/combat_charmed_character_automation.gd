## Resolves movement and automatic attacks for charmed party actors.

class_name CombatCharmedCharacterAutomation
extends RefCounted

var _context: CombatContext
var _monster_actions: CombatMonsterActions
var _occupancy: CombatOccupancyRules
var failure_result: CombatFlowResult


func _init(context: CombatContext, monster_actions: CombatMonsterActions) -> void:
	_context = context
	_monster_actions = monster_actions
	_occupancy = CombatOccupancyRules.new(context)


func advance_charmed_character(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	if combat.pending_reaction == null and not _occupancy.hostile_adjacent_ids(state, actor.id).is_empty(): return 0
	_context.actions().prepare_character_turn(combat, actor)
	var terrain := _monster_actions.battle_terrain_set(content, combat.battlefield)
	var targets: Array[String] = []
	for id: String in combat.battlefield.actors.actor_ids():
		if id != actor.id and not CombatAiTargetFacts.character_is_friendly(state, actor, id) and CombatAiTargetFacts.health(state, id) > 0:
			targets.append(id)
	var visited: Array[Vector2i] = []
	while actor.movement > 0 and actor.current_health > 0:
		if combat.pending_reaction != null:
			var continuation: int = _context.reactions().continue_pending_reaction(state, content, rng, events)
			if continuation != 0: return continuation
		if not _occupancy.hostile_adjacent_ids(state, actor.id).is_empty(): return 0
		var origin := combat.battlefield.actors.actor_position(actor.id)
		visited.append(origin)
		var retained := combat.turns.active_turn.target_id
		var candidates: Array[String] = [retained] if targets.has(retained) else targets
		var step: BattlefieldStepResult = null
		for target_id: String in candidates:
			step = _context.battlefield.probe_path_step_toward_actors(combat.battlefield, terrain, actor.id, [target_id], actor.movement, [], visited)
			if step.allowed:
				combat.turns.active_turn.target_id = target_id
				break
		if step == null or not step.allowed: return 0
		combat.pending_reaction = CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, origin, step.destination, step.movement_cost)
		combat.pending_reaction.set_origin_hostiles([])
		combat.pending_reaction.set_phase(CombatReactionState.GUARD_BEFORE, [])
	return 0


func process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	failure_result = null
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
		events.append(DomainEvent.new(&"combat_monster_action_unavailable", {"actorId": actor.id, "action": "advance", "reason": "no-legal-contact"}))
		return false
	var target_index := 0
	var equipment := _context.equipment.combat_equipment(actor, content.items.definitions())
	if not equipment.valid:
		failure_result = CombatFlowResult.failed(equipment.error_code, equipment.error_message)
		return false
	var active_turn := state.combat.turns.begin_active_turn()
	if active_turn == null:
		failure_result = CombatFlowResult.failed(&"invalid_combat_turn", "Charmed actor '%s' has no active turn." % actor.id)
		return false
	if target_index < character_targets.size():
		return _resolve_charmed_attack_character(state, content, actor, equipment, character_targets[target_index], active_turn, rng, events)
	var monster_target := monster_targets[target_index - character_targets.size()]
	var target_definition := content.combat.monster_by_id(monster_target.definition_id)
	if target_definition == null:
		failure_result = CombatFlowResult.failed(&"missing_monster_definition", "Charmed target '%s' has no monster definition." % monster_target.id)
		return false
	active_turn.physical_action_committed = true
	var resolution := _context.combat.resolve_character_attack(actor, equipment, monster_target, target_definition, rng, state.clock.day(), false, true, state.combat.dropped_items.can_queue())
	if resolution.total_damage() > 0:
		state.combat.actor_statuses.mark_attacked(monster_target.id)
	if resolution.fumbled and not _context.actions().events().commit_character_fumble(state, content, actor, equipment, events):
		failure_result = CombatFlowResult.failed(&"invalid_fumble_state", "Charmed actor '%s' could not commit its fumble." % actor.id)
		return false
	var event = _context.actions().events().character_attack_event(actor.id, monster_target.id, &"monster", resolution, equipment.melee_weapon != null)
	_context.actions().events().append_character_attack_audio(events, actor, equipment, resolution, &"monster")
	event.payload["automatic"] = true
	events.append(event)
	if resolution.reflected:
		_context.actions().mark_character_bleeding(state, actor, resolution.killed)
		CombatOccupancyRules.remove_defeated_position(state.combat, actor.id, resolution.killed)
		return false
	var death_macro_requested = resolution.killed and _context.actions().events().request_monster_death_macro(monster_target, target_definition, events)
	CombatOccupancyRules.remove_defeated_position(state.combat, monster_target.id, resolution.killed and not death_macro_requested)
	return death_macro_requested


func _resolve_charmed_attack_character(state: GameState, content: RealmzContent, actor: CharacterState, equipment: CharacterCombatEquipment, target: CharacterState, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	var target_equipment := _context.equipment.combat_equipment(target, content.items.definitions())
	if not target_equipment.valid:
		failure_result = CombatFlowResult.failed(target_equipment.error_code, target_equipment.error_message)
		return false
	active_turn.physical_action_committed = true
	var resolution := _context.combat.resolve_character_attack_character(actor, equipment, target, target_equipment, rng, false, true, state.combat.dropped_items.can_queue())
	if resolution.total_damage() > 0:
		state.combat.actor_statuses.mark_attacked(target.id)
	if resolution.fumbled and not _context.actions().events().commit_character_fumble(state, content, actor, equipment, events):
		failure_result = CombatFlowResult.failed(&"invalid_fumble_state", "Charmed actor '%s' could not commit its fumble." % actor.id)
		return false
	var character_event = _context.actions().events().character_attack_event(actor.id, target.id, &"character", resolution, equipment.melee_weapon != null)
	_context.actions().events().append_character_attack_audio(events, actor, equipment, resolution, &"character")
	character_event.payload["automatic"] = true
	events.append(character_event)
	var victim: CharacterState = actor if resolution.reflected else target
	_context.actions().mark_character_bleeding(state, victim, resolution.killed)
	CombatOccupancyRules.remove_defeated_position(state.combat, victim.id, resolution.killed)
	return false
