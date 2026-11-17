## Applies one save editor party change to a replayed game state, using the same admission
## and ally rules as play. A refusal returns the reason; nothing here touches the saved file.

class_name SaveEditOperations
extends RefCounted

## Draft-added allies use their own identity family so later in-play allies, which number
## from the save's instance counter, can never reuse one.
const ALLY_PREFIX := "party.ally.edited."
const _EQUIPMENT_HELD := "The scenario is holding this party's equipment, so party members can't join or leave until it is returned."

var _content: RealmzContent
var _rules: RealmzRules


func _init(content: RealmzContent, rules: RealmzRules) -> void:
	_content = content
	_rules = rules


## Applies `operation` to `state`; returns "" or why it is refused. `members` maps
## character IDs to their `SaveEditMember`.
func apply(state: GameState, operation: Dictionary, members: Dictionary[String, SaveEditMember]) -> String:
	var kind: StringName = operation.kind
	match kind:
		&"difficulty":
			var difficulty: int = operation.value
			return _difficulty(state, difficulty)
		&"monster_set":
			var monster_set: int = operation.value
			return _monster_set(state, monster_set)
		&"add_character":
			var character_id: String = operation.character_id
			return _add_character(state, members[character_id] if members.has(character_id) else null)
		&"drop_character":
			var dropped_id: String = operation.character_id
			return _drop_character(state, dropped_id)
		&"add_ally":
			var definition_id: String = operation.definition_id
			var new_ally_id: String = operation.ally_id
			var ally_seed: int = operation.seed
			return _add_ally(state, definition_id, new_ally_id, ally_seed)
		&"dismiss_ally":
			var ally_id: String = operation.ally_id
			return _dismiss_ally(state, ally_id)
	return "That change isn't supported."


## Monster definitions that may join as allies under the state's monster set, by name.
func ally_candidates(state: GameState) -> Array[MonsterDefinition]:
	var result: Array[MonsterDefinition] = []
	for base: MonsterDefinition in _content.combat.definitions():
		var definition := _content.combat.monster_by_id_for_set(base.id, state.monster_set)
		if definition != null and ally_error(definition).is_empty():
			result.append(definition)
	result.sort_custom(_by_name)
	return result


static func _by_name(left: MonsterDefinition, right: MonsterDefinition) -> bool:
	if left.name != right.name:
		return left.name.naturalnocasecmp_to(right.name) < 0
	return left.classic_id < right.classic_id


## Why `definition` can't travel as an ally, matching the Classic add-ally operation, or "".
func ally_error(definition: MonsterDefinition) -> String:
	if definition == null:
		return "That creature isn't in this scenario."
	var consumption := MonsterConsumptionProbe.inspect(_content, definition)
	if consumption.outcome != MonsterConsumptionProbe.Outcome.USABLE:
		return "%s can't travel as an ally: %s" % [definition.name, consumption.reason]
	var table_error := MonsterRules.random_weapon_table_error(definition)
	if not table_error.is_empty():
		return "%s can't travel as an ally: %s" % [definition.name, table_error]
	return ""


func _difficulty(state: GameState, value: int) -> String:
	if value < -2 or value > 2:
		return "Difficulty must be between Novice and Veteran."
	state.difficulty = value
	return ""


func _monster_set(state: GameState, value: int) -> String:
	if not _content.combat.available_monster_sets().has(value):
		return "This scenario doesn't offer that monster set."
	state.monster_set = value
	return ""


func _add_character(state: GameState, member: SaveEditMember) -> String:
	if member == null:
		return "That character is no longer part of this draft."
	if state.party.equipment_storage_active:
		return _EQUIPMENT_HELD
	var maximum := clampi(_content.campaign.restrictions.maximum_party_size, 1, 6)
	if state.party.characters().size() >= maximum:
		return "This scenario allows no more than %d characters." % maximum
	var character := CharacterStateCodec.copy(member.state())
	var context := SessionWorkflowContext.new(_content, state, _rules, null, null, null)
	var failure := PartyAdmissionRules.validate(context, character)
	if failure != null:
		return failure.error_message
	if not state.party.add_character(character):
		return "%s couldn't join the party." % character.name
	return ""


func _drop_character(state: GameState, character_id: String) -> String:
	if state.party.equipment_storage_active:
		return _EQUIPMENT_HELD
	if state.party.character_by_id(character_id) == null:
		return "That character isn't in the party."
	if state.party.characters().size() <= 1:
		return "The party needs at least one character."
	state.party.remove_character(character_id)
	state.set_combat_auto(character_id, false)
	return ""


func _add_ally(state: GameState, definition_id: String, ally_id: String, seed_value: int) -> String:
	var definition := _content.combat.monster_by_id_for_set(definition_id, state.monster_set)
	var error := ally_error(definition)
	if not error.is_empty():
		return error
	# Fresh dice, as Level Up uses: the save's own random sequence stays exactly as saved.
	var ally := _rules.monsters.build_monster(definition, ally_id, 0, state.difficulty, state.clock.day(), RealmzRng.new(seed_value))
	if ally == null or not state.party.add_ally(ally):
		return "%s couldn't join as an ally." % definition.name
	return ""


func _dismiss_ally(state: GameState, ally_id: String) -> String:
	var kept: Array[MonsterState] = []
	for ally: MonsterState in state.party.allies():
		if ally.id != ally_id:
			kept.append(ally)
	if kept.size() == state.party.allies().size():
		return "That ally is no longer traveling with the party."
	state.party.set_allies(kept)
	return ""
