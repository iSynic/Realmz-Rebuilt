## Runs deterministic party Auto activations and tactical pursuit.

class_name CombatPartyAutomation
extends RefCounted

const MAX_AUTO_OPERATIONS: int = 256
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

var _context: CombatContext
var _ai_scoring: CombatAiScoring
var _monster_actions: CombatMonsterActions


func _init(context: CombatContext) -> void:
	_context = context
	_ai_scoring = CombatAiScoring.new(context)
	_monster_actions = CombatMonsterActions.new(context)


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
	var visited_anchors: Array[Vector2i] = [state.combat.battlefield.actors.actor_position(actor.id)]
	var starting_round := state.combat.turns.round_number
	var operation_count := 0
	var previous_processing = _context.processing_auto
	_context.processing_auto = true
	while operation_count < MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed and state.combat.turns.active_actor_id() == actor_id and state.combat.turns.round_number == starting_round:
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
		if state.combat != null and state.combat.battlefield.actors.has_actor(actor.id):
			var current_anchor := state.combat.battlefield.actors.actor_position(actor.id)
			if not visited_anchors.has(current_anchor):
				visited_anchors.append(current_anchor)
		if result.completed or _events_include(result.events, &"monster_death_macro_requested") or state.combat.pending_monster_attack != null:
			break
	_context.processing_auto = previous_processing
	if operation_count >= MAX_AUTO_OPERATIONS and state.combat != null and not state.combat.completed and state.combat.turns.active_actor_id() == actor_id and state.combat.turns.round_number == starting_round:
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
	var actor_id := state.combat.turns.active_actor_id()
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.traitor or not state.combat_auto_enabled(actor_id):
		return CombatFlowResult.succeeded([])
	return _run_auto_turn_unchecked(state, content, actor_id, rng)


func _auto_unavailable(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	if state == null or content == null or rng == null or state.combat == null or state.combat.completed:
		return CombatFlowResult.failed(&"combat_auto_unavailable", "No active battle can resolve an automatic turn.")
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0 or actor.traitor or state.combat.turns.active_actor_id() != actor_id:
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
		if character.id != actor.id and character.current_health > 0 and character.traitor != actor.traitor and combat.battlefield.actors.has_actor(character.id):
			candidates.append(character.id)
	for monster: MonsterState in combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor != actor.traitor and combat.battlefield.actors.has_actor(monster.id):
			candidates.append(monster.id)
	if candidates.is_empty():
		return CombatFlowResult.failed(&"combat_auto_no_target", "No opposed battlefield combatant remains.")
	var target_id := combat.turns.active_turn.target_id
	if not candidates.has(target_id):
		target_id = candidates[rng.draw_between(0, candidates.size() - 1, StringName("combat.auto.%s.target" % actor.id))]
		combat.turns.active_turn.target_id = target_id
	var origin := combat.battlefield.actors.actor_position(actor.id)
	var terrain_set := _monster_actions.battle_terrain_set(content, combat.battlefield)
	var swappable_ids: Array[String] = []
	if combat.battlefield.actors.actor_size(actor.id) == 0:
		for character: CharacterState in state.party.characters():
			if character.id != actor.id and character.current_health > 0 and character.traitor == actor.traitor and combat.battlefield.actors.has_actor(character.id) and combat.battlefield.actors.actor_size(character.id) == 0:
				swappable_ids.append(character.id)
		for monster: MonsterState in combat.roster.monsters():
			if monster.current_health > 0 and monster.traitor == actor.traitor and combat.battlefield.actors.has_actor(monster.id) and combat.battlefield.actors.actor_size(monster.id) == 0:
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
	if battlefield == null or movement < 5 or not battlefield.actors.has_actor(actor_id) or not battlefield.actors.has_actor(target_id):
		return null
	var origin := battlefield.actors.actor_position(actor_id)
	var target := battlefield.actors.actor_position(target_id)
	var destination := origin + Vector2i(signi(target.x - origin.x), signi(target.y - origin.y))
	if visited_anchors.has(destination) or not swappable_ids.has(battlefield.actors.actor_at(destination, actor_id)):
		return null
	return BattlefieldStepResult.permitted(destination, 5)


static func _events_include(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false
