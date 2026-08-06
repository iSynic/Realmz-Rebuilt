class_name ClassicInventoryOperations
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rules = rules


func toggle_equipment_storage(capture: bool) -> ScenarioRuntimeOperationResult:
	if capture:
		_rules.economy.pool_party_wealth(_game_state.party)
		var changed := _game_state.party.capture_equipment()
		if changed:
			for character: CharacterState in _game_state.party.characters():
				character.carried_load = 0
		return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"equipment_stored", {"changed": changed, "source": "classic"})])
	var restored := _game_state.party.restore_equipment()
	if restored:
		_recalculate_party_loads()
	return ScenarioRuntimeOperationResult.completed(restored, [DomainEvent.new(&"equipment_restored", {"changed": restored, "source": "classic"})])


func _recalculate_party_loads() -> void:
	for character: CharacterState in _game_state.party.characters():
		var total := character.money.gold + character.money.gems + character.money.jewelry * 15
		for instance: ItemInstance in character.inventory():
			var definition := _content.item_by_id(instance.definition_id)
			if definition != null:
				total += definition.instance_weight(instance.charges)
		character.carried_load = maxi(0, total)
