## Owns battlefield hostility queries and defeated-actor occupancy cleanup.

class_name CombatOccupancyRules
extends RefCounted

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func hostile_adjacent_ids(state: GameState, actor_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	var result: Array[String] = []
	if state == null or state.combat == null or state.combat.battlefield == null:
		return result
	var actor_traitor := false
	var character := state.party.character_by_id(actor_id)
	if character != null:
		actor_traitor = character.traitor
	else:
		var monster := state.combat.roster.monster_by_id(actor_id)
		if monster == null:
			return result
		actor_traitor = monster.traitor
	var adjacent_ids := _context.battlefield.adjacent_actor_ids(state.combat.battlefield, actor_id, anchor_override)
	# Castle scans numeric combat slots: party members first, then monsters in
	# authored runtime order. Stable IDs must not accidentally redefine reactions.
	for candidate_character: CharacterState in state.party.characters():
		if adjacent_ids.has(candidate_character.id) and candidate_character.current_health > 0 and candidate_character.traitor != actor_traitor:
			result.append(candidate_character.id)
	for candidate_monster: MonsterState in state.combat.roster.monsters():
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
		candidate_id = state.combat.battlefield.actors.actor_at(destination_or_target, actor_id)
	if candidate_id.is_empty():
		return ""
	var actor := state.party.character_by_id(actor_id)
	if actor == null or actor.current_health <= 0:
		return ""
	var monster := state.combat.roster.monster_by_id(candidate_id)
	if monster != null:
		return candidate_id if monster.current_health > 0 and monster.traitor != actor.traitor else ""
	var character := state.party.character_by_id(candidate_id)
	return candidate_id if character != null and character.current_health > 0 and character.traitor != actor.traitor else ""


static func remove_defeated_position(combat: CombatState, actor_id: String, defeated: bool) -> void:
	if not defeated or combat == null or combat.battlefield == null:
		return
	if combat.roster.monster_by_id(actor_id) != null:
		combat.battlefield.actors.remove_monster(actor_id)
	else:
		combat.battlefield.actors.remove_character(actor_id)


static func remove_all_defeated_positions(state: GameState) -> void:
	if state == null or state.combat == null or state.combat.battlefield == null:
		return
	for monster: MonsterState in state.combat.roster.monsters():
		remove_defeated_position(state.combat, monster.id, monster.current_health <= 0)
	for character: CharacterState in state.party.characters():
		remove_defeated_position(state.combat, character.id, character.current_health <= 0)
