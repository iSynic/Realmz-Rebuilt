class_name ClassicCombatOperations
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rules = rules


func cause_fumble(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 122 requires message and sound fields.")
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"combat_fumble_skipped", {"reason": "no-active-battle", "source": "classic"})])
	var actor_id := str(context.get("combatantId", _game_state.combat.active_actor_id()))
	var character := _game_state.party.character_by_id(actor_id)
	var fumbled_definition_id := ""
	if character != null:
		for instance: ItemInstance in character.inventory():
			if not instance.equipped:
				continue
			var definition := _content.item_by_id(instance.definition_id)
			var removed := _rules.inventory.remove_item(character, instance.id, definition)
			if removed != null:
				removed.equipped = false
				_game_state.party.add_storage_item(removed)
				fumbled_definition_id = removed.definition_id
			break
	else:
		var monster := _game_state.combat.monster_by_id(actor_id)
		if monster != null and not monster.weapon_id.is_empty():
			fumbled_definition_id = monster.weapon_id
			monster.weapon_id = ""
	var changed := not fumbled_definition_id.is_empty()
	var events: Array[DomainEvent] = []
	if int(action.extra_code[1]) != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": int(action.extra_code[1]), "source": "classic"}))
	if int(action.extra_code[0]) != 0:
		var message := _content.message_by_id(absi(int(action.extra_code[0])))
		if message != null:
			events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic"}))
	events.append(DomainEvent.new(&"combatant_fumbled", {"combatantId": actor_id, "itemId": fumbled_definition_id, "changed": changed, "source": "classic"}))
	return ScenarioRuntimeOperationResult.completed(changed, events)
