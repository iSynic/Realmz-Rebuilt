## Projects and applies Castle's carried-item Drop action during Treasure.

class_name ClassicRewardDropSupport
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rules = rules


func project(character: CharacterState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for item: ItemInstance in character.inventory():
		var definition := _content.items.item_by_id(item.definition_id)
		if definition == null:
			continue
		var shown := InventoryRules.presentation_definition(item, definition, _content.items)
		var probe := _rules.equipment.classic_unequip_probe(character, item, definition, _content.items.definitions()) if item.equipped else InventoryActionProbe.permit()
		rows.append({
			"instanceId": item.id,
			"name": shown.name if item.identified else shown.unidentified_name,
			"equipped": item.equipped,
			"enabled": probe.allowed,
			"reason": probe.reason,
		})
	return rows


func drop(body: InteractionResponse.TreasureBody, events: Array[DomainEvent]) -> Dictionary:
	if body.character_id.is_empty() or body.instance_id.is_empty():
		return {"code": "invalid_interaction_response", "message": "Treasure Drop requires a character and carried item."}
	var character := _game_state.party.character_by_id(body.character_id)
	var item: ItemInstance = null
	if character != null:
		for carried: ItemInstance in character.inventory():
			if carried.id == body.instance_id:
				item = carried
				break
	var definition: ItemDefinition = null if item == null else _content.items.item_by_id(item.definition_id)
	if character == null or item == null or definition == null:
		return {"code": "reward_drop_unavailable", "message": "That character no longer carries the selected item."}
	var race := _content.characters.race_by_id(character.race_id)
	var caste := _content.characters.caste_by_id(character.caste_id)
	if race == null or caste == null:
		return {"code": "reward_drop_unavailable", "message": "The character's movement rules are unavailable."}
	if item.equipped:
		var unequipped := _rules.equipment.unequip_classic(character, item, definition, _content.items.definitions(), race, _game_state.party.conditions)
		if not unequipped.allowed:
			return {"code": "reward_drop_unavailable", "message": unequipped.reason}
	if _rules.inventory.remove_item(character, item.id, definition) == null:
		return {"code": "reward_drop_unavailable", "message": "The selected item could not be dropped."}
	_rules.characters.recalculate_movement(character, race, caste.movement_bonus)
	events.append(DomainEvent.new(&"item_dropped", {"characterId": character.id, "instanceId": item.id, "itemId": definition.id}))
	events.append(DomainEvent.new(&"sound_requested", {"soundId": 655, "waitForCompletion": false, "source": "classic-treasure-drop"}))
	return {}
