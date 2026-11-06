## Moves frightened party actors away from opponents until their movement or route ends.

class_name CombatFrightenedCharacterAutomation
extends RefCounted

const ENDED := 0
const RELEASED := 4

var _context: CombatContext
var _monster_actions: CombatMonsterActions


func _init(context: CombatContext, monster_actions: CombatMonsterActions) -> void:
	_context = context
	_monster_actions = monster_actions


## Returns ENDED, RELEASED, or the reaction result that suspended the flight.
func run(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	var combat := state.combat
	var terrain := _monster_actions.battle_terrain_set(content, combat.battlefield)
	var operation_guard := 256
	while terrain != null and operation_guard > 0 and actor.current_health > 0:
		operation_guard -= 1
		if combat.pending_reaction != null:
			var attempted_from := combat.pending_reaction.origin
			var reaction_result: int = _context.reactions().continue_pending_reaction(state, content, rng, events)
			if reaction_result != ENDED:
				return reaction_result
			if combat.battlefield.actors.actor_position(actor.id) == attempted_from:
				break
			continue
		var threat_id := _threat_id(state, actor)
		if actor.movement <= 0 or threat_id.is_empty():
			break
		combat.turns.active_turn.target_id = threat_id
		# Castle combatinfo-combatchoice.c:1569-1573 reverses the step toward its target.
		var step := _context.battlefield.probe_monster_step_away(combat.battlefield, terrain, actor.id, combat.battlefield.actors.actor_position(threat_id), actor.movement, rng)
		if not step.allowed:
			break
		if _context.reactions().probe_edge_retreat(combat, actor.id, step.destination).allowed:
			if actor.traitor:
				break
			return _release_at_edge(combat, actor, step.destination, events)
		var origin_hostiles := _context.automation().hostile_adjacent_ids(state, actor.id)
		combat.pending_reaction = CombatReactionState.new(CombatReactionState.CHARACTER_MOVE, actor.id, combat.battlefield.actors.actor_position(actor.id), step.destination, step.movement_cost)
		combat.pending_reaction.set_origin_hostiles(origin_hostiles)
		combat.pending_reaction.set_phase(CombatReactionState.GUARD_BEFORE, _context.reactions().guarding_actor_ids(state, origin_hostiles))
	# Castle guards when flight runs out of movement or juke passes.
	combat.actor_statuses.set_guarding(actor.id, true)
	return ENDED


func _threat_id(state: GameState, actor: CharacterState) -> String:
	# Castle flees an adjacent opponent, then its retained target; FD-COMBAT-024 uses the nearest, not a random draw.
	var adjacent := _context.automation().hostile_adjacent_ids(state, actor.id)
	if not adjacent.is_empty():
		return adjacent[0]
	var actors := state.combat.battlefield.actors
	var retained := state.combat.turns.active_turn.target_id
	var origin := actors.actor_position(actor.id)
	var nearest := ""
	var nearest_distance := 0x7fff_ffff
	for id: String in actors.actor_ids():
		if id == actor.id or CombatAiTargetFacts.character_is_friendly(state, actor, id) or CombatAiTargetFacts.health(state, id) <= 0:
			continue
		if id == retained:
			return id
		var offset := actors.actor_position(id) - origin
		var distance := maxi(absi(offset.x), absi(offset.y))
		if distance < nearest_distance:
			nearest = id
			nearest_distance = distance
	return nearest


func _release_at_edge(combat: CombatState, actor: CharacterState, destination: Vector2i, events: Array[DomainEvent]) -> int:
	# Departure FD-COMBAT-024: Castle asks Embrace Cowardice or Stay and Fight from a view-dependent
	# edge check; Rebuilt returns the activation at the retreat band, where edge movement asks it.
	combat.turns.active_turn.action = &""
	combat.turns.invalidate_undo()
	events.append(DomainEvent.new(&"combat_fear_control_released", {"actorId": actor.id, "destination": [destination.x, destination.y], "reason": "battlefield-edge"}))
	return RELEASED
