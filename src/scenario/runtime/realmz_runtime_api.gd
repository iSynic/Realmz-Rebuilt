class_name RealmzRuntimeApi
extends RefCounted

const SUPPORTED_SAFE_CAPABILITIES: Array[String] = [
	"core.combat.start",
	"core.economy.grant-treasure",
	"core.economy.take-gold",
	"core.inventory.grant-item",
	"core.party.camp",
	"core.presentation.choice",
	"core.presentation.text",
	"core.state.read",
	"core.state.write",
	"core.time.advance",
]

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _action_state: ScenarioActionState
var _rules: RealmzRules
var _character_operations: ClassicCharacterOperations
var _combat_operations: ClassicCombatOperations
var _control_flow_operations: ClassicControlFlowOperations
var _inventory_operations: ClassicInventoryOperations


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, action_state: ScenarioActionState, rules: RealmzRules = null) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_action_state = action_state
	_rules = rules if rules != null else RealmzRules.new()
	_character_operations = ClassicCharacterOperations.new(_content, _game_state, _rng, _rules)
	_combat_operations = ClassicCombatOperations.new(_content, _game_state, _rules)
	_control_flow_operations = ClassicControlFlowOperations.new(_content, _game_state)
	_inventory_operations = ClassicInventoryOperations.new(_content, _game_state, _rules)


func execute_classic(action: ClassicActionDefinition, request_id: String, context: Dictionary = {}) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		-23, 23:
			return _mutate_random_region(action, action.opcode == -23)
		-14, 14:
			return _request_character_selection(action, request_id, action.opcode == -14)
		1:
			var message_id := absi(action.operand_id)
			var message := _content.message_by_id(message_id)
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 1 references unavailable message %d." % action.operand_id)
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new("message_shown", {"messageId": message_id, "text": message.text, "source": "classic", "classicClick": action.operand_id > 0})])
		4:
			var encounter := _content.simple_encounter_by_id(action.operand_id)
			if encounter == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "Classic opcode 4 references unavailable Simple Encounter %d." % action.operand_id)
			var prompt := _content.message_by_id(absi(encounter.prompt_message_id))
			if prompt == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
			var options: Array[Dictionary] = []
			var option_indexes: Array[int] = []
			var responses := encounter.responses()
			for option_index: int in responses.size():
				if _game_state.simple_option_is_eliminated(encounter.id, option_index):
					continue
				var response: SimpleEncounterResponse = responses[option_index]
				options.append({"id": response.id, "label": response.label})
				option_indexes.append(option_index)
			if options.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Simple Encounter %d has no remaining responses." % encounter.id)
			var request := InteractionRequest.new(request_id, &"encounter_choice", {"encounterKind": "simple", "encounterId": encounter.id, "prompt": prompt.text, "options": options, "canBackOut": encounter.can_back_out})
			return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-simple-encounter", "encounterId": encounter.id, "gosub": action.gosub, "optionIndexes": option_indexes})
		5:
			return _request_complex_encounter(action, request_id)
		3:
			return _request_classic_choice(action, request_id)
		6:
			return _request_shop(action.operand_id, request_id)
		7:
			return _control_flow_operations.replace_scenario_program(action, context)
		8:
			return _control_flow_operations.branch_to_trigger_program(action, context)
		2, 48, 56, 107:
			var battle_id := action.operand_id
			if action.opcode in [48, 56, 107] and not action.extra_code.is_empty():
				battle_id = absi(action.extra_code[0])
			return _start_battle(battle_id, request_id, action.opcode)
		9:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"sound_requested", {"soundId": absi(action.operand_id), "source": "classic"})])
		10:
			return _grant_treasure(action.operand_id)
		11:
			var experience := maxi(0, action.operand_id)
			for character: CharacterState in _game_state.party.characters():
				if character.current_health > 0:
					character.experience += experience
			return ScenarioRuntimeOperationResult.completed(experience, [DomainEvent.new(&"experience_granted", {"amount": experience, "target": "living-party", "source": "classic"})])
		12:
			return _mutate_tile(action)
		13:
			return _mutate_triggers(action)
		15, 16:
			return _apply_health(action, action.opcode == 16)
		17, 18:
			return _character_operations.apply_scenario_spell(action, action.opcode == 18)
		19:
			return _show_random_message(action)
		21:
			return _branch_on_item(action)
		22:
			return _mutate_items(action)
		24:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"action_point_finished", {"reason": "classic-opcode-24"})], {"kind": "finish"})
		25:
			var trigger_id := String(context.get("triggerId", ""))
			if trigger_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"missing_trigger_context", "Classic opcode 25 requires an Action Point origin.")
			_game_state.world.disable_trigger(trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"trigger_disabled", {"triggerId": trigger_id, "source": "classic"})])
		26:
			return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, &"acknowledge", {"prompt": "Continue", "soundId": 30005}), {"kind": "classic-acknowledge"})
		27:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"picture_requested", {"pictureId": absi(action.operand_id), "source": "classic"})])
		28:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"map_redraw_requested", {"source": "classic"})])
		29:
			var map := _content.world.map_by_type_and_index(&"land", absi(action.operand_id))
			if map == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 29 references unavailable land map %d." % action.operand_id)
			_game_state.world.acquire_map(map.id)
			return ScenarioRuntimeOperationResult.completed(map.id, [DomainEvent.new(&"map_acquired", {"mapId": map.id, "display": action.operand_id < 0})])
		30:
			return _filter_character_selection(action)
		31:
			return _request_character_ability(action, request_id)
		32:
			return _request_temple(action, request_id)
		33:
			var values := action.extra_code
			var amount := absi(action.operand_id) if values.is_empty() else absi(values[0])
			var kind := WealthState.Kind.GOLD if values.size() < 2 else clampi(values[1], WealthState.Kind.GOLD, WealthState.Kind.JEWELRY) as WealthState.Kind
			var paid := _rules.economy.take(_game_state.party, amount, kind)
			return ScenarioRuntimeOperationResult.completed(paid, [DomainEvent.new(&"wealth_taken", {"amount": amount, "kind": kind, "paid": paid, "source": "classic"})])
		35:
			var encounter_id := int(context.get("encounterId", -1))
			if context.get("encounterKind") != "simple" or not _game_state.eliminate_simple_option(encounter_id, action.operand_id - 1):
				return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_context", "Classic opcode 35 requires a Simple Encounter response context.")
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_eliminated", {"encounterId": encounter_id, "optionIndex": action.operand_id - 1})])
		36:
			return _inventory_operations.toggle_equipment_storage(action.operand_id != 0)
		37:
			return _move_between_maps(action, true)
		38:
			return _branch_on_item_result(action)
		40:
			return _branch_on_party_condition(action)
		42:
			return _percent_branch(action, context)
		43:
			return _apply_classic_condition(action)
		45:
			return _move_between_maps(action, false)
		46:
			return _branch_on_quest(action)
		47:
			var quest_id := absi(action.operand_id)
			if not _game_state.set_quest_value(quest_id, 0 if action.operand_id < 0 else 1):
				return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 47 references quest %d outside 0 through 99." % quest_id)
			return ScenarioRuntimeOperationResult.completed(_game_state.quest_value(quest_id), [DomainEvent.new(&"quest_changed", {"questId": quest_id, "value": _game_state.quest_value(quest_id)})])
		49:
			return _request_banking(request_id)
		51:
			return _mutate_shop(action)
		52:
			return _select_characters_by_misc(action)
		54:
			return _mutate_timed_encounter(action)
		88:
			var removed := _remove_classic_ally(absi(action.operand_id))
			return ScenarioRuntimeOperationResult.completed(removed, [DomainEvent.new(&"allies_removed", {"classicMonsterId": absi(action.operand_id), "count": removed})])
		89:
			return _add_classic_ally(absi(action.operand_id))
		99:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"classic_control_marker", {"opcode": 99, "operandId": action.operand_id})])
		104:
			_game_state.random_encounters_enabled = action.operand_id != 0
			return ScenarioRuntimeOperationResult.completed(_game_state.random_encounters_enabled, [DomainEvent.new(&"random_encounters_changed", {"enabled": _game_state.random_encounters_enabled})])
		121:
			return _deanimate_lower_undead()
		122:
			return _combat_operations.cause_fumble(action, context)
		124:
			return _spawn_classic_monsters(action)
		_:
			return ScenarioRuntimeOperationResult.failed(&"unsupported_classic_opcode", "No Realmz Runtime API operation owns Classic opcode %d." % action.opcode)


func resolve_program_id(program_id: String) -> String:
	return _control_flow_operations.resolve_program_id(program_id)


func execute_safe(capability: String, arguments: Dictionary, request_id: String) -> ScenarioRuntimeOperationResult:
	match capability:
		"core.party.camp":
			if not arguments.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Camp does not accept arguments.")
			if not _game_state.camping_allowed or _game_state.combat != null and not _game_state.combat.completed:
				return ScenarioRuntimeOperationResult.failed(&"camping_unavailable", "The party cannot camp in the current state.")
			return ScenarioRuntimeOperationResult.completed(true, _rules.clock.camp(_game_state))
		"core.time.advance":
			if not _whole_number(arguments.get("minutes")) or int(arguments["minutes"]) < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Advance Time requires non-negative integer minutes.")
			return ScenarioRuntimeOperationResult.completed(true, _rules.clock.advance_minutes(_game_state, int(arguments["minutes"])))
		"core.inventory.grant-item":
			if not arguments.get("characterId") is String or not arguments.get("itemId") is String or arguments.get("identified", false) is not bool:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Grant Item requires characterId, itemId, and optional identified bool.")
			return _grant_item(arguments["characterId"], arguments["itemId"], arguments.get("identified", false))
		"core.economy.grant-treasure":
			if not arguments.get("treasureId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Grant Treasure requires a stable treasureId.")
			var treasure := _content.treasure_by_id(arguments["treasureId"])
			if treasure == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Treasure '%s' is unavailable." % arguments["treasureId"])
			return _grant_treasure_definition(treasure)
		"core.economy.take-gold":
			if not _whole_number(arguments.get("amount")) or int(arguments["amount"]) < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Take Gold requires a non-negative integer amount.")
			var amount := int(arguments["amount"])
			var paid := _rules.economy.take(_game_state.party, amount, WealthState.Kind.GOLD)
			return ScenarioRuntimeOperationResult.completed(paid, [DomainEvent.new(&"wealth_taken", {"amount": amount, "kind": WealthState.Kind.GOLD, "paid": paid, "source": "scenario-action"})])
		"core.combat.start":
			if not arguments.get("battleId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Start Battle requires a stable battleId.")
			var battle := _content.battle_by_id(arguments["battleId"])
			if battle == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Battle '%s' is unavailable." % arguments["battleId"])
			return _start_battle_definition(battle, request_id, "scenario-action")
		"core.presentation.text":
			if not arguments.get("text") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Show Text requires a string 'text' argument.")
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new("message_shown", {"text": arguments["text"], "source": "scenario-action"})])
		"core.presentation.choice":
			if not arguments.get("prompt") is String or not arguments.get("options") is Array or arguments["options"].is_empty() or arguments["options"].size() > 256:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Choice requires a prompt and one to 256 options.")
			var options: Array[Dictionary] = []
			for index: int in range(arguments["options"].size()):
				var label: Variant = arguments["options"][index]
				if not label is String:
					return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Choice option %d is not a string." % index)
				options.append({"id": "choice:%d" % index, "label": label})
			var request := InteractionRequest.new(request_id, &"scenario_choice", {"prompt": arguments["prompt"], "options": options})
			return ScenarioRuntimeOperationResult.waiting(request, {"kind": "safe-choice", "optionCount": options.size()})
		"core.state.read":
			var state_identity := _state_identity(arguments)
			if state_identity.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "State Read requires a valid scope and name or numeric ID.")
			return ScenarioRuntimeOperationResult.completed(_action_state.read(state_identity[0], state_identity[1], state_identity[2], arguments.get("default")))
		"core.state.write":
			var state_identity := _state_identity(arguments)
			if state_identity.is_empty() or not arguments.has("value"):
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "State Write requires a valid scope, name or numeric ID, and value.")
			if not _action_state.write(state_identity[0], state_identity[1], state_identity[2], arguments["value"]):
				return ScenarioRuntimeOperationResult.failed(&"scenario_state_limit", "Scenario Action state rejected an unsafe or oversized value.")
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new("scenario_state_changed", {"scope": state_identity[0], "ownerId": state_identity[1], "name": state_identity[2]})])
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_action_capability", "Scenario Action capability '%s' is not available." % capability)


func resume_safe(continuation: Dictionary, response: InteractionResponse, request_id: String = "") -> ScenarioRuntimeOperationResult:
	match continuation.get("kind"):
		"safe-choice":
			var option_count: int = int(continuation.get("optionCount", 0))
			if response.kind != &"scenario_choice" or not response.payload.get("index") is int or response.payload["index"] < 0 or response.payload["index"] >= option_count:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Scenario choice response must identify an available option.")
			return ScenarioRuntimeOperationResult.completed(response.payload["index"])
		"safe-combat":
			return _resume_battle(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Scenario Action interaction continuation is unavailable.")


func simple_encounter_by_id(encounter_id: int) -> SimpleEncounterDefinition:
	return _content.simple_encounter_by_id(encounter_id)


func write_action_state(state_scope: String, owner_id: String, name: String, value: Variant) -> bool:
	return _action_state.write(state_scope, owner_id, name, value)


func read_action_state(state_scope: String, owner_id: String, name: String, default_value: Variant = null) -> Variant:
	return _action_state.read(state_scope, owner_id, name, default_value)


func resume_classic(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	match continuation.get("kind"):
		"classic-simple-encounter":
			return _resume_simple_encounter(continuation, response)
		"classic-complex-encounter":
			return _resume_complex_encounter(continuation, response, request_id)
		"classic-acknowledge":
			if response.kind != &"acknowledge":
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Acknowledgement response has the wrong kind.")
			return ScenarioRuntimeOperationResult.completed(true)
		"classic-combat":
			return _resume_battle(continuation, response, request_id)
		"classic-character-selection":
			return _resume_character_selection(continuation, response)
		"classic-character-ability":
			return _resume_character_ability(continuation, response)
		"classic-choice":
			return _resume_classic_choice(continuation, response)
		"classic-shop":
			return _resume_shop(continuation, response, request_id)
		"classic-temple":
			return _resume_temple(continuation, response, request_id)
		"classic-banking":
			return _resume_banking(continuation, response, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Classic interaction continuation is unavailable.")


func _resume_simple_encounter(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var encounter := _content.simple_encounter_by_id(int(continuation.get("encounterId", -1)))
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Simple Encounter is unavailable.")
	if response.kind != &"encounter_choice":
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response has the wrong kind.")
	if response.payload.get("cancelled", false) == true:
		if not encounter.can_back_out:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Simple Encounter cannot be cancelled.")
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "simple", "encounterId": encounter.id})], {"kind": "finish"})
	if not _whole_number(response.payload.get("index")):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response must contain a choice index.")
	var selected_index := int(response.payload["index"])
	var option_indexes: Variant = continuation.get("optionIndexes", [])
	if option_indexes is Array and not option_indexes.is_empty():
		if selected_index < 0 or selected_index >= option_indexes.size() or not _whole_number(option_indexes[selected_index]):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the available choices.")
		selected_index = int(option_indexes[selected_index])
	var selected := encounter.response_at(selected_index)
	if selected == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the authored choices.")
	_game_state.record_encounter_attempt(&"simple", encounter.id)
	return ScenarioRuntimeOperationResult.completed(selected.id, [DomainEvent.new(&"encounter_response_selected", {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index})], {"kind": "branch-program", "programId": selected.result_program_id, "gosub": bool(continuation.get("gosub", false)), "context": {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index}})


func _request_complex_encounter(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var encounter := _content.complex_encounter_by_id(action.operand_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "Classic opcode 5 references unavailable Complex Encounter %d." % action.operand_id)
	var request := _complex_encounter_request(encounter, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter %d has no available responses." % encounter.id)
	return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-complex-encounter", "encounterId": encounter.id, "gosub": action.gosub})


func _complex_encounter_request(encounter: ComplexEncounterDefinition, request_id: String) -> InteractionRequest:
	var prompt := _content.message_by_id(absi(encounter.prompt_message_id))
	if prompt == null:
		return null
	var actions: Array[Dictionary] = []
	if encounter.action_result != 0:
		var labels := encounter.action_labels()
		for slot: int in labels.size():
			var label := labels[slot].strip_edges()
			if not label.is_empty() and label != "*":
				actions.append({"id": "choice:%d" % slot, "kind": "choice", "slot": slot, "label": label})
	if encounter.word_result != 0:
		actions.append({"id": "word", "kind": "word", "label": "Speak a word"})
	for spell_id: int in encounter.spell_ids():
		if spell_id != 0:
			actions.append({"id": "spell", "kind": "spell", "label": "Cast a spell"})
			break
	for item_id: int in encounter.item_ids():
		if item_id != 0:
			actions.append({"id": "item", "kind": "item", "label": "Use an item"})
			break
	if encounter.thief:
		var thief_encounter := _content.thief_encounter_by_id(encounter.thief_success)
		if thief_encounter != null:
			var flags := _game_state.thief_encounter_type_flags(thief_encounter)
			var labels: Array[String] = ["Acrobatics", "Detect Trap", "Disarm Trap", "Hear Noise", "Force Lock", "Move Silently", "Pick Lock", "Pick Pocket"]
			for index: int in labels.size():
				if flags[index]:
					actions.append({"id": "thief:%d" % index, "kind": "thief", "actionIndex": index, "label": labels[index]})
	if encounter.can_back_out:
		actions.append({"id": "back", "kind": "back", "label": "Back out"})
	if actions.is_empty():
		return null
	var characters: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	var spells: Array[Dictionary] = []
	var seen_items: Dictionary = {}
	var seen_spells: Dictionary = {}
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0:
			characters.append({"id": character.id, "name": character.name})
		for instance: ItemInstance in character.inventory():
			var item := _content.item_by_id(instance.definition_id)
			if item != null and not seen_items.has(item.classic_id):
				seen_items[item.classic_id] = true
				items.append({"classicItemId": item.classic_id, "name": item.name})
		for spell_id: String in character.known_spells():
			var spell := _content.spell_by_id(spell_id)
			if spell != null and not seen_spells.has(spell.classic_id):
				seen_spells[spell.classic_id] = true
				spells.append({"classicSpellId": spell.classic_id, "name": spell.name})
	return InteractionRequest.new(request_id, &"complex_encounter", {"encounterKind": "complex", "encounterId": encounter.id, "prompt": prompt.text, "actions": actions, "characters": characters, "items": items, "spells": spells, "canBackOut": encounter.can_back_out})


func _resume_complex_encounter(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var encounter := _content.complex_encounter_by_id(int(continuation.get("encounterId", -1)))
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Complex Encounter is unavailable.")
	if response.kind != &"complex_encounter" or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex Encounter response requires an action.")
	var action: String = response.payload["action"]
	var outcome := 0
	var context: Dictionary = {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": action}
	var events: Array[DomainEvent] = []
	match action:
		"back":
			if not encounter.can_back_out:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Complex Encounter cannot be cancelled.")
			return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "complex", "encounterId": encounter.id})], {"kind": "finish"})
		"choice":
			if not _whole_number(response.payload.get("slot")):
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action response requires an authored slot.")
			var slot := int(response.payload["slot"])
			var labels := encounter.action_labels()
			if slot < 0 or slot >= labels.size() or labels[slot].strip_edges() in ["", "*"]:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action slot is unavailable.")
			outcome = encounter.action_result
			context["optionSlot"] = slot
		"word":
			if not response.payload.get("word") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex word response requires text.")
			outcome = _complex_word_outcome(encounter, response.payload["word"])
		"spell":
			if not _whole_number(response.payload.get("classicSpellId")):
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex spell response requires a Classic spell ID.")
			outcome = _complex_catalog_outcome(encounter.spell_ids(), encounter.spell_results(), int(response.payload["classicSpellId"]))
		"item":
			if not _whole_number(response.payload.get("classicItemId")):
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex item response requires a Classic item ID.")
			var item_id := int(response.payload["classicItemId"])
			if not _party_has_classic_item(absi(item_id)):
				return ScenarioRuntimeOperationResult.failed(&"item_not_owned", "The party does not possess the selected Complex Encounter item.")
			outcome = _complex_catalog_outcome(encounter.item_ids(), encounter.item_results(), item_id)
		"thief":
			return _resume_thief_encounter(encounter, continuation, response, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex Encounter action '%s' is unavailable." % action)
	if outcome < 1 or outcome > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Complex Encounter produced invalid result %d." % outcome)
	_game_state.record_encounter_attempt(&"complex", encounter.id)
	events.append(DomainEvent.new(&"encounter_response_selected", {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": action, "outcome": outcome}))
	return _complex_outcome(encounter, outcome, bool(continuation.get("gosub", false)), context, events)


func _complex_outcome(encounter: ComplexEncounterDefinition, outcome: int, gosub: bool, context: Dictionary, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var program_id := encounter.result_program_id(outcome)
	if program_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Complex Encounter result is outside 1 through 4.")
	return ScenarioRuntimeOperationResult.completed(outcome, events, {"kind": "branch-program", "programId": program_id, "gosub": gosub, "context": context})


func _complex_word_outcome(encounter: ComplexEncounterDefinition, entered_word: String) -> int:
	if entered_word.is_empty() or encounter.word_result == 0:
		return 4
	var expected := encounter.expected_word().left(40)
	var first_space := expected.find(" ")
	if first_space >= 0:
		expected = expected.left(first_space)
	return encounter.word_result if entered_word.to_lower().begins_with(expected) else 4


func _complex_catalog_outcome(ids: Array[int], results: Array[int], selected_id: int) -> int:
	for index: int in mini(ids.size(), results.size()):
		if ids[index] != 0 and absi(ids[index]) == absi(selected_id):
			return results[index]
	return 4


func _resume_thief_encounter(encounter: ComplexEncounterDefinition, continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var thief_encounter := _content.thief_encounter_by_id(encounter.thief_success)
	if thief_encounter == null or not _whole_number(response.payload.get("actionIndex")) or not response.payload.get("characterId") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter response requires an available action and character.")
	var character := _game_state.party.character_by_id(response.payload["characterId"])
	var action_index := int(response.payload["actionIndex"])
	var flags := _game_state.thief_encounter_type_flags(thief_encounter)
	if character == null or character.current_health <= 0 or action_index < 0 or action_index >= 8 or not flags[action_index]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter action or character is unavailable.")
	flags[action_index] = false
	var trap_armed := flags[9]
	if trap_armed and action_index in [4, 6, 7]:
		if action_index == 4:
			flags[action_index] = true
		return _spring_thief_trap(encounter, thief_encounter, continuation, character, flags, request_id)
	var modifiers := thief_encounter.modifiers()
	var chance := clampi(character.special_value(action_index) + modifiers[action_index], 0, 100)
	if action_index in [2, 4, 6, 7]:
		chance = mini(chance, 90)
	var succeeded := _rng.draw(100, &"classic.thief-encounter") <= chance
	if succeeded:
		if action_index == 1 and trap_armed:
			flags[2] = true
		elif action_index == 2:
			flags[9] = false
	elif trap_armed and action_index != 1:
		return _spring_thief_trap(encounter, thief_encounter, continuation, character, flags, request_id)
	_game_state.set_thief_encounter_type_flags(thief_encounter, flags)
	var codes := thief_encounter.success_codes() if succeeded else thief_encounter.failure_codes()
	var outcome := codes[action_index]
	var text_ids := thief_encounter.success_text() if succeeded else thief_encounter.failure_text()
	var sound_ids := thief_encounter.success_sounds() if succeeded else thief_encounter.failure_sounds()
	var events: Array[DomainEvent] = [DomainEvent.new(&"thief_action_resolved", {"encounterId": encounter.id, "thiefEncounterId": thief_encounter.id, "characterId": character.id, "actionIndex": action_index, "chancePercent": chance, "succeeded": succeeded, "messageId": text_ids[action_index], "soundId": sound_ids[action_index]})]
	if outcome == 0:
		var request := _complex_encounter_request(encounter, request_id)
		if request == null:
			return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter has no available responses after the Thief action.")
		return ScenarioRuntimeOperationResult.waiting(request, continuation, events)
	if outcome < 1 or outcome > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Thief Encounter produced invalid result %d." % outcome)
	_game_state.record_encounter_attempt(&"complex", encounter.id)
	return _complex_outcome(encounter, outcome, bool(continuation.get("gosub", false)), {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": "thief", "actionIndex": action_index, "characterId": character.id}, events)


func _spring_thief_trap(encounter: ComplexEncounterDefinition, thief_encounter: ThiefEncounterDefinition, continuation: Dictionary, character: CharacterState, flags: Array[bool], request_id: String) -> ScenarioRuntimeOperationResult:
	flags[9] = false
	flags[1] = false
	flags[6] = true
	_game_state.set_thief_encounter_type_flags(thief_encounter, flags)
	var damage := _rng.draw_between(thief_encounter.low_damage, thief_encounter.high_damage, &"classic.thief-trap-damage") if thief_encounter.high_damage >= thief_encounter.low_damage and thief_encounter.high_damage > 0 else 0
	if damage > 0:
		character.current_health = maxi(-32_768, character.current_health - damage)
	var events: Array[DomainEvent] = [DomainEvent.new(&"thief_trap_sprung", {"encounterId": encounter.id, "thiefEncounterId": thief_encounter.id, "characterId": character.id, "damage": damage, "spellId": thief_encounter.spell_id})]
	var request := _complex_encounter_request(encounter, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter has no available responses after its trap.")
	return ScenarioRuntimeOperationResult.waiting(request, continuation, events)


func _state_identity(arguments: Dictionary) -> Array[String]:
	var state_scope := str(arguments.get("scope", "campaign"))
	var owner_id := str(arguments.get("ownerId", ""))
	var name_value: Variant = arguments.get("name", arguments.get("id"))
	if state_scope.is_empty() or name_value == null or (not name_value is String and not name_value is int):
		return []
	return [state_scope, owner_id, str(name_value)]


func _request_classic_choice(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 3 requires a five-value Extra Code row.")
	var yes_id := action.extra_code[3]
	var no_id := action.extra_code[4]
	var yes_message := _content.message_by_id(yes_id)
	var no_message := _content.message_by_id(no_id)
	var request := InteractionRequest.new(request_id, &"yes_no", {"yesId": yes_id, "yesLabel": yes_message.text if yes_message != null else "Yes", "noId": no_id, "noLabel": no_message.text if no_message != null else "No"})
	return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-choice", "values": action.extra_code.duplicate(), "gosub": action.gosub})


func _resume_classic_choice(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	if response.kind != &"yes_no" or response.payload.get("accepted") is not bool:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic choice response requires an accepted bool.")
	var values: Array = continuation.get("values", [])
	if values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_vm_continuation", "Classic choice continuation is malformed.")
	var apply_result: bool = bool(response.payload["accepted"]) != (int(values[0]) != 0)
	if not apply_result:
		return ScenarioRuntimeOperationResult.completed(false)
	match int(values[1]):
		0:
			return ScenarioRuntimeOperationResult.completed(true, [], {"kind": "finish"})
		1:
			return _branch_xap(int(values[2]), bool(continuation.get("gosub", false)))
		4:
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_elimination_requested")])
	return ScenarioRuntimeOperationResult.failed(&"unsupported_choice_target", "Classic choice branch mode %d is not available." % int(values[1]))


func _request_character_selection(action: ClassicActionDefinition, request_id: String, invert: bool) -> ScenarioRuntimeOperationResult:
	var count := absi(action.operand_id)
	if count < 1:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_count", "Classic character picker requests no characters.")
	var eligible: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if action.operand_id < 0 or character.current_health > 0:
			eligible.append({"id": character.id, "name": character.name, "currentHealth": character.current_health})
	if eligible.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_eligible_characters", "Classic character picker has no eligible party members.")
	count = mini(count, eligible.size())
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, &"character_selection", {"count": count, "eligible": eligible, "allowDead": action.operand_id < 0}), {"kind": "classic-character-selection", "count": count, "allowDead": action.operand_id < 0, "invert": invert})


func _resume_character_selection(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	if response.kind != &"character_selection" or response.payload.get("characterIds") is not Array:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection response requires characterIds.")
	var requested: Array = response.payload["characterIds"]
	if requested.size() != int(continuation.get("count", 0)):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection returned the wrong number of characters.")
	var picked: Array[String] = []
	for value: Variant in requested:
		if not value is String or picked.has(value):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection contains an invalid or duplicate ID.")
		var character := _game_state.party.character_by_id(value)
		if character == null or not bool(continuation.get("allowDead", false)) and character.current_health <= 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection includes an ineligible party member.")
		picked.append(value)
	var selected := picked
	if bool(continuation.get("invert", false)):
		selected = []
		for character: CharacterState in _game_state.party.characters():
			if not picked.has(character.id):
				selected.append(character.id)
	if not _game_state.set_selected_character_ids(selected):
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_selection", "Selected character state rejected the response.")
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected", {"characterIds": selected, "inverted": bool(continuation.get("invert", false))})])


func _request_character_ability(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 31 requires a five-value Extra Code row.")
	var eligible: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0:
			eligible.append({"id": character.id, "name": character.name})
	if eligible.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_eligible_characters", "Classic ability check has no living party member.")
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, &"character_selection", {"count": 1, "eligible": eligible, "allowDead": false}), {"kind": "classic-character-ability", "values": action.extra_code.duplicate(), "gosub": action.gosub})


func _resume_character_ability(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	if response.kind != &"character_selection" or response.payload.get("characterIds") is not Array or response.payload["characterIds"].size() != 1 or not response.payload["characterIds"][0] is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check requires one selected character.")
	var character := _game_state.party.character_by_id(response.payload["characterIds"][0])
	var values: Array = continuation.get("values", [])
	if character == null or character.current_health <= 0 or values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check selected an unavailable character.")
	_game_state.set_selected_character_ids([character.id])
	var check_index := int(values[0])
	var modifier := int(values[1])
	var attribute_check := int(values[2]) != 0
	var check_value := _character_attribute(character, check_index) if attribute_check else character.special_value(check_index)
	var roll := _rng.draw(25 if attribute_check else 100, &"classic.character-ability")
	var passed := roll - modifier < check_value if attribute_check else roll <= check_value + modifier
	var target_id := int(values[3] if passed else values[4])
	var event := DomainEvent.new(&"character_ability_checked", {"characterId": character.id, "checkIndex": check_index, "attribute": attribute_check, "value": check_value, "modifier": modifier, "roll": roll, "passed": passed})
	var branch := _branch_xap(target_id, bool(continuation.get("gosub", false)))
	branch.events.append(event)
	return branch


func _filter_character_selection(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 30 requires a five-value Extra Code row.")
	var values := action.extra_code
	var candidates := _game_state.selected_characters()
	if int(values[2]) in [1, 2]:
		candidates = []
		for character: CharacterState in _game_state.party.characters():
			if int(values[2]) == 1 or character.current_health > 0:
				candidates.append(character)
	var selected: Array[String] = []
	var checks: Array[Dictionary] = []
	var attribute_check := int(values[3]) != 0
	var check_index := absi(int(values[0]))
	for character: CharacterState in candidates:
		var check_value := _character_attribute(character, check_index) if attribute_check else character.special_value(check_index)
		var roll := _rng.draw(25 if attribute_check else 100, &"classic.filter-character")
		var passed := roll - int(values[1]) < check_value if attribute_check else roll <= check_value + int(values[1])
		if passed != (int(values[0]) < 0):
			selected.append(character.id)
		checks.append({"characterId": character.id, "roll": roll, "value": check_value, "passed": passed})
	_game_state.set_selected_character_ids(selected)
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"character_selection_filtered", {"characterIds": selected, "checks": checks})])


func _apply_health(action: ClassicActionDefinition, whole_party: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5 or action.extra_code[2] < action.extra_code[1]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_health_effect", "Classic health action requires a valid Extra Code roll range.")
	var targets := _game_state.party.characters() if whole_party else _game_state.selected_characters()
	var hits: Array[Dictionary] = []
	for character: CharacterState in targets:
		var roll := _rng.draw_between(action.extra_code[1], action.extra_code[2], &"classic.health-effect")
		var amount := action.extra_code[0] * roll
		var previous := character.current_health
		character.current_health = mini(character.maximum_health, maxi(-32_768, character.current_health + amount))
		hits.append({"characterId": character.id, "previousHealth": previous, "health": character.current_health, "amount": character.current_health - previous})
	return ScenarioRuntimeOperationResult.completed(hits, [DomainEvent.new(&"party_health_changed", {"targets": "party" if whole_party else "selected", "hits": hits, "soundId": action.extra_code[3], "messageId": action.extra_code[4]})])


func _show_random_message(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	var message_ids: Array[int] = []
	for value: int in action.extra_code:
		if value != 0 and _content.message_by_id(value) != null:
			message_ids.append(value)
	if message_ids.is_empty() and _content.message_by_id(action.operand_id) != null:
		message_ids.append(action.operand_id)
	if message_ids.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 19 has no available message.")
	var selected_id := message_ids[_rng.draw_between(0, message_ids.size() - 1, &"classic.random-message")]
	return ScenarioRuntimeOperationResult.completed(selected_id, [DomainEvent.new(&"message_shown", {"messageId": selected_id, "text": _content.message_by_id(selected_id).text, "source": "classic-random"})])


func _branch_on_item(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 21 requires a five-value Extra Code row.")
	var values := action.extra_code
	var possessed := _party_has_classic_item(absi(values[0]))
	if possessed:
		return _branch_target_mode(values[1], values[3], action.gosub)
	match int(values[2]):
		0:
			return _branch_target_mode(values[1], values[4], action.gosub)
		1:
			return ScenarioRuntimeOperationResult.completed(false)
		2:
			var message := _content.message_by_id(values[4])
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic item branch references unavailable message %d." % values[4])
			return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-item-check"})], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.failed(&"invalid_item_branch", "Classic item possession branch has an invalid failure mode.")


func _branch_on_item_result(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 38 requires a five-value Extra Code row.")
	var possessed := _party_has_classic_item(absi(action.extra_code[0]))
	var test_mode := action.extra_code[1]
	if test_mode == 2 or test_mode == 0 and not possessed or test_mode == 1 and possessed:
		return _branch_from_values(action.extra_code, false)
	if test_mode not in [0, 1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_item_branch", "Classic item result branch has an invalid test mode.")
	return ScenarioRuntimeOperationResult.completed(false)


func _mutate_items(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 22 requires a five-value Extra Code row.")
	var source := _content.item_by_classic_id(absi(action.extra_code[0]))
	if source == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic item mutation references unavailable item %d." % action.extra_code[0])
	var operation := action.extra_code[2]
	var maximum := action.extra_code[1]
	if maximum < 0 or operation not in [1, 2, 3]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_item_mutation", "Classic item mutation has an invalid count or operation.")
	var replacement := _content.item_by_classic_id(absi(action.extra_code[4])) if operation == 3 else null
	if operation == 3 and replacement == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic item replacement is unavailable.")
	var changed := 0
	for character: CharacterState in _game_state.party.characters():
		var items := character.inventory()
		for index: int in range(items.size() - 1, -1, -1):
			if maximum > 0 and changed >= maximum:
				break
			var instance: ItemInstance = items[index]
			if instance.definition_id != source.id:
				continue
			match operation:
				1:
					_rules.inventory.remove_item(character, instance.id, source)
				2:
					var previous_weight := source.instance_weight(instance.charges)
					instance.charges = clampi(instance.charges + action.extra_code[3], -1, 32_767)
					character.carried_load = maxi(0, character.carried_load - previous_weight + source.instance_weight(instance.charges))
				3:
					var was_equipped := instance.equipped
					_rules.inventory.remove_item(character, instance.id, source)
					var replacement_instance := _rules.inventory.add_item(character, replacement, _game_state.next_instance_id("classic.replacement"), false)
					if replacement_instance == null:
						return ScenarioRuntimeOperationResult.failed(&"inventory_full", "Classic replacement item no longer fits the character inventory.")
					if was_equipped and _rules.inventory.can_equip(character, replacement):
						replacement_instance.equipped = true
			changed += 1
		if maximum > 0 and changed >= maximum:
			break
	return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"party_items_changed", {"itemId": source.id, "operation": operation, "changed": changed})])


func _party_has_classic_item(classic_item_id: int, minimum_charges: int = -1, equipped_only: bool = false) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in _game_state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id == definition.id and (minimum_charges < 0 or instance.charges >= minimum_charges) and (not equipped_only or instance.equipped):
				return true
	return false


func _percent_branch(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 42 requires a five-value Extra Code row.")
	var roll := _rng.draw(100, &"classic.percent-branch")
	if roll > action.extra_code[0]:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": false})])
	var event := DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": true})
	match action.extra_code[1]:
		-2:
			var trigger_id := String(context.get("triggerId", ""))
			if not trigger_id.is_empty():
				_game_state.world.disable_trigger(trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [event], {"kind": "finish"})
		1:
			var branch := _branch_from_values(action.extra_code, false)
			branch.events.append(event)
			return branch
		2:
			return ScenarioRuntimeOperationResult.completed(true, [event], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.completed(true, [event])


func _branch_on_quest(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 46 requires a five-value Extra Code row.")
	var is_set := _game_state.quest_is_set(action.extra_code[0])
	var condition := action.extra_code[1]
	var should_branch := condition == 2 or condition == 1 and is_set or condition == 0 and not is_set
	if not should_branch:
		return ScenarioRuntimeOperationResult.completed(false)
	return _branch_from_values(action.extra_code, action.gosub)


func _branch_on_party_condition(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 40 requires a five-value Extra Code row.")
	var required_state := action.extra_code[0]
	var condition_index := action.extra_code[3]
	if required_state not in [1, 2] or condition_index < 0 or condition_index >= ConditionSet.PARTY_COUNT:
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_condition", "Classic party-condition branch has an invalid state or condition.")
	var active := _game_state.party.conditions.is_active(condition_index)
	if required_state == 1 and not active or required_state == 2 and active:
		return ScenarioRuntimeOperationResult.completed(false)
	return _branch_target_mode(action.extra_code[1] - 1, action.extra_code[2], action.gosub)


func _branch_from_values(values: Array[int], gosub: bool) -> ScenarioRuntimeOperationResult:
	match values[2]:
		0:
			return _branch_xap(values[3], gosub)
		3:
			return ScenarioRuntimeOperationResult.completed(true, [], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_mode", "Classic branch mode %d is not available in this execution context." % values[2])


func _branch_target_mode(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if mode == 0:
		return _branch_xap(target_id, gosub)
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is not available in this execution context." % mode)


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(false)
	return ScenarioRuntimeOperationResult.completed(true, [], {"kind": "branch-xap", "targetId": target_id, "gosub": gosub})


func _mutate_random_region(action: ClassicActionDefinition, dungeon: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic random-region mutation requires a five-value Extra Code row.")
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic random-region mutation references unavailable map %d." % action.extra_code[0])
	var region := map.random_region_by_index(action.extra_code[1])
	if region == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_random_region", "Classic random-region mutation references unavailable rectangle %d." % action.extra_code[1])
	var previous := _game_state.world.random_region(region)
	var battle_min := previous.battle_minimum if action.extra_code[3] < 0 else action.extra_code[3]
	var battle_max := previous.battle_maximum if action.extra_code[4] < 0 else action.extra_code[4]
	var updated := RandomRegionState.new(region.id, action.extra_code[2], battle_min, battle_max, previous.random_door_percents())
	_game_state.world.set_random_region(updated)
	return ScenarioRuntimeOperationResult.completed(updated.id, [DomainEvent.new(&"random_region_changed", {"regionId": updated.id, "chanceTenThousand": updated.chance_ten_thousand, "battleMinimum": updated.battle_minimum, "battleMaximum": updated.battle_maximum})])


func _mutate_tile(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 12 requires a five-value Extra Code row.")
	var dungeon := action.extra_code[4] != 0
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[1]) if dungeon else Vector2i(action.extra_code[1], action.extra_code[2])
	if map == null or map.topology.cell_at(coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map_cell", "Classic tile mutation references an unavailable map cell.")
	var terrain_id := "classic.terrain.%d" % action.extra_code[3]
	_game_state.world.replace_terrain(map.id, coordinate, terrain_id)
	return ScenarioRuntimeOperationResult.completed(terrain_id, [DomainEvent.new(&"tile_replaced", {"mapId": map.id, "x": coordinate.x, "y": coordinate.y, "terrainId": terrain_id, "source": "classic"})])


func _mutate_triggers(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 13 requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	var level_type := current_map.level_type
	if action.extra_code[3] < 0:
		level_type = &"dungeon"
	elif action.extra_code[3] > 0:
		level_type = &"land"
	var map := _content.world.map_by_type_and_index(level_type, action.extra_code[0])
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic trigger mutation references unavailable map %d." % action.extra_code[0])
	var record_indexes: Array[int] = []
	if action.extra_code[1] != 0:
		record_indexes.append(action.extra_code[1])
	if action.extra_code[3] != 0:
		for record_index: int in range(absi(action.extra_code[3]), absi(action.extra_code[4]) + 1):
			if not record_indexes.has(record_index):
				record_indexes.append(record_index)
	var changed: Array[String] = []
	for record_index: int in record_indexes:
		var trigger := _content.trigger_by_map_record(map.id, record_index)
		if trigger == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_trigger", "Classic trigger mutation references unavailable record %d on map '%s'." % [record_index, map.id])
		_game_state.world.set_trigger_chance(trigger.id, action.extra_code[2])
		changed.append(trigger.id)
	return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"trigger_chances_changed", {"triggerIds": changed, "chancePercent": action.extra_code[2]})])


func _move_between_maps(action: ClassicActionDefinition, dungeon_move: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic map movement requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	var target_type := (&"dungeon" if action.extra_code[0] == 0 else &"land") if dungeon_move else current_map.level_type
	var map_index := action.extra_code[1] if dungeon_move else action.extra_code[0]
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[3]) if dungeon_move else Vector2i(action.extra_code[1], action.extra_code[2])
	var target_map := _content.world.map_by_type_and_index(target_type, map_index)
	if target_map == null or target_map.topology.cell_at(coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_teleport", "Classic map movement references an unavailable destination.")
	var source_map_id := _game_state.party.map_id
	var source_coordinate := _game_state.party.coordinate
	_game_state.party.map_id = target_map.id
	_game_state.party.coordinate = coordinate
	_game_state.world.mark_visited(target_map.id, coordinate)
	return ScenarioRuntimeOperationResult.completed(target_map.id, [DomainEvent.new(&"party_teleported", {"sourceMapId": source_map_id, "sourceX": source_coordinate.x, "sourceY": source_coordinate.y, "mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "soundId": action.extra_code[4] if dungeon_move else action.extra_code[3], "messageId": 0 if dungeon_move else action.extra_code[4]})])


func _mutate_timed_encounter(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 54 requires a five-value Extra Code row.")
	var encounter_id := action.extra_code[0]
	var current := _game_state.timed_encounter_override(encounter_id)
	if action.extra_code[1] > -1:
		current["percent"] = action.extra_code[1]
	if action.extra_code[2] > -1:
		current["increment"] = action.extra_code[2]
	if action.extra_code[3] != 0:
		current["day"] = _game_state.clock.day()
	if action.extra_code[4] > -1:
		current["day"] = int(current.get("day", 0)) + action.extra_code[4]
	_game_state.set_timed_encounter_override(encounter_id, current)
	return ScenarioRuntimeOperationResult.completed(current, [DomainEvent.new(&"timed_encounter_changed", {"encounterId": encounter_id, "state": current})])


func _request_shop(classic_shop_id: int, request_id: String) -> ScenarioRuntimeOperationResult:
	var shop := _content.shop_by_classic_id(absi(classic_shop_id))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic opcode 6 references unavailable shop %d." % classic_shop_id)
	return ScenarioRuntimeOperationResult.waiting(_shop_request(shop, request_id), {"kind": "classic-shop", "shopId": shop.id}, [DomainEvent.new(&"shop_opened", {"shopId": shop.id})])


func _shop_request(shop: ShopDefinition, request_id: String) -> InteractionRequest:
	var stock: Array[Dictionary] = []
	var characters: Array[Dictionary] = []
	var item_ids := shop.item_ids()
	for index: int in item_ids.size():
		var item := _content.item_by_id(item_ids[index])
		if item == null:
			continue
		stock.append({"index": index, "itemId": item.id, "name": item.name, "quantity": _game_state.shop_quantity(shop, index), "buyPrice": _shop_item_price(item, shop, false), "sellPrice": _shop_item_price(item, shop, true)})
	for character: CharacterState in _game_state.party.characters():
		var inventory: Array[Dictionary] = []
		for instance: ItemInstance in character.inventory():
			var definition := _content.item_by_id(instance.definition_id)
			if definition != null:
				inventory.append({"instanceId": instance.id, "itemId": definition.id, "name": definition.name, "sellPrice": _shop_item_price(definition, shop, true)})
		characters.append({"id": character.id, "name": character.name, "inventory": inventory})
	return InteractionRequest.new(request_id, &"shop_action", {"shopId": shop.id, "inflationPercent": _game_state.shop_inflation(shop), "stock": stock, "characters": characters, "actions": ["buy", "sell", "leave"]})


func _resume_shop(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != &"shop_action" or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop response requires an action string.")
	var shop := _content.shop_by_id(String(continuation.get("shopId", "")))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "The pending shop is unavailable.")
	var operation: String = response.payload["action"]
	if operation == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_closed", {"shopId": shop.id})])
	var events: Array[DomainEvent] = []
	match operation:
		"buy":
			if not _whole_number(response.payload.get("stockIndex")) or not response.payload.get("characterId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop buy requires stockIndex and characterId.")
			var stock_index := int(response.payload["stockIndex"])
			var item_ids := shop.item_ids()
			if stock_index < 0 or stock_index >= item_ids.size() or _game_state.shop_quantity(shop, stock_index) < 1:
				return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "The selected shop item is out of stock.")
			var character := _game_state.party.character_by_id(response.payload["characterId"])
			var item := _content.item_by_id(item_ids[stock_index])
			if character == null or item == null or character.inventory().size() >= InventoryRules.MAX_ITEMS or character.carried_load + item.instance_weight(item.initial_charges) > character.maximum_load:
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The selected character cannot carry this item.")
			var price := _shop_item_price(item, shop, false)
			if not _rules.economy.take(_game_state.party, price, WealthState.Kind.GOLD):
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "The party cannot afford this item.")
			var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("shop.item"), false)
			if instance == null:
				_game_state.party.pooled_wealth.gold += price
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The item could not be added after purchase validation.")
			_game_state.set_shop_quantity(shop, stock_index, _game_state.shop_quantity(shop, stock_index) - 1)
			events.append(DomainEvent.new(&"shop_item_bought", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		"sell":
			if not response.payload.get("characterId") is String or not response.payload.get("instanceId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop sell requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(response.payload["characterId"])
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The shop sale character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == response.payload["instanceId"]:
					instance = candidate
					break
			if instance == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item_instance", "The sold item instance is unavailable.")
			var item := _content.item_by_id(instance.definition_id)
			var price := _shop_item_price(item, shop, true)
			_rules.inventory.remove_item(character, instance.id, item)
			_game_state.party.pooled_wealth.gold += price
			events.append(DomainEvent.new(&"shop_item_sold", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_shop_action", "Shop action '%s' is unavailable." % operation)
	return ScenarioRuntimeOperationResult.waiting(_shop_request(shop, request_id), continuation, events)


func _mutate_shop(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 51 requires a five-value Extra Code row.")
	var shop := _content.shop_by_classic_id(absi(action.extra_code[0]))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic shop mutation references unavailable shop %d." % action.extra_code[0])
	var inflation := maxi(0, _game_state.shop_inflation(shop) + action.extra_code[1])
	_game_state.set_shop_inflation(shop, inflation)
	var stock_index := -1
	if action.extra_code[2] != 0:
		var item := _content.item_by_classic_id(absi(action.extra_code[2]))
		if item == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic shop mutation references unavailable item %d." % action.extra_code[2])
		stock_index = shop.item_ids().find(item.id)
		if stock_index < 0:
			return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "Classic shop mutation item is not stocked by the shop.")
		_game_state.set_shop_quantity(shop, stock_index, _game_state.shop_quantity(shop, stock_index) + action.extra_code[3])
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_changed", {"shopId": shop.id, "inflationPercent": inflation, "stockIndex": stock_index, "quantity": _game_state.shop_quantity(shop, stock_index) if stock_index >= 0 else 0})])


func _shop_item_price(item: ItemDefinition, shop: ShopDefinition, selling: bool) -> int:
	var multiplier := _game_state.shop_inflation(shop)
	if selling:
		multiplier = mini(multiplier, 100)
	return mini(32_000, int(float(absi(item.cost) * multiplier) / 100.0))


func _request_temple(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	return ScenarioRuntimeOperationResult.waiting(_temple_request(action.operand_id, request_id), {"kind": "classic-temple", "costPercent": action.operand_id}, [DomainEvent.new(&"temple_opened", {"costPercent": action.operand_id})])


func _temple_request(cost_percent: int, request_id: String) -> InteractionRequest:
	var characters: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		characters.append({"id": character.id, "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health})
	return InteractionRequest.new(request_id, &"temple_action", {"costPercent": cost_percent, "characters": characters, "actions": ["heal", "leave"]})


func _resume_temple(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != &"temple_action" or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple response requires an action.")
	if response.payload["action"] == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed")])
	if response.payload["action"] != "heal" or not response.payload.get("characterId") is String:
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_action", "Temple action is unavailable.")
	var character := _game_state.party.character_by_id(response.payload["characterId"])
	if character == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_character", "Temple healing target is unavailable.")
	var missing := maxi(0, character.maximum_health - character.current_health)
	var cost := maxi(1, int(float(missing * absi(int(continuation.get("costPercent", 100)))) / 100.0)) if missing > 0 else 0
	if cost > 0 and not _rules.economy.take(_game_state.party, cost, WealthState.Kind.GOLD):
		return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "The party cannot afford temple healing.")
	character.current_health = character.maximum_health
	return ScenarioRuntimeOperationResult.waiting(_temple_request(int(continuation.get("costPercent", 100)), request_id), continuation, [DomainEvent.new(&"temple_healing_applied", {"characterId": character.id, "cost": cost, "health": character.current_health})])


func _request_banking(request_id: String) -> ScenarioRuntimeOperationResult:
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id), {"kind": "classic-banking"}, [DomainEvent.new(&"bank_opened")])


func _bank_request(request_id: String) -> InteractionRequest:
	return InteractionRequest.new(request_id, &"bank_action", {"carriedGold": _game_state.party.pooled_wealth.gold, "bankedGold": _game_state.party.banked_wealth.gold, "actions": ["deposit", "withdraw", "leave"]})


func _resume_banking(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != &"bank_action" or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank response requires an action.")
	var action: String = response.payload["action"]
	if action == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"bank_closed")])
	if not _whole_number(response.payload.get("amount")) or int(response.payload["amount"]) < 0:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank transfer requires a non-negative amount.")
	var amount := int(response.payload["amount"])
	match action:
		"deposit":
			if amount > _game_state.party.pooled_wealth.gold:
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "The party cannot deposit more gold than it carries.")
			_game_state.party.pooled_wealth.gold -= amount
			_game_state.party.banked_wealth.gold += amount
		"withdraw":
			if amount > _game_state.party.banked_wealth.gold:
				return ScenarioRuntimeOperationResult.failed(&"insufficient_banked_gold", "The party cannot withdraw more gold than it banked.")
			_game_state.party.banked_wealth.gold -= amount
			_game_state.party.pooled_wealth.gold += amount
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_bank_action", "Bank action '%s' is unavailable." % action)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id), continuation, [DomainEvent.new(&"bank_transfer_completed", {"action": action, "amount": amount})])


func _select_characters_by_misc(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 52 requires a five-value Extra Code row.")
	var selector := action.extra_code[0]
	var value := action.extra_code[1]
	var source_mode := action.extra_code[2]
	if selector < 0 or selector > 8 or source_mode < 0 or source_mode > 2:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_selector", "Classic miscellaneous character selector is invalid.")
	var candidates := _game_state.selected_characters()
	if source_mode != 2:
		candidates = []
		for character: CharacterState in _game_state.party.characters():
			if source_mode == 0 or character.current_health > 0:
				candidates.append(character)
	var selected: Array[String] = []
	var party := _game_state.party.characters()
	for character: CharacterState in candidates:
		var matches := false
		match selector:
			0:
				matches = character.movement < value
			1:
				matches = party.find(character) < value
			2:
				matches = _character_has_classic_item(character, absi(value), false)
			3:
				matches = _rng.draw(100, &"classic.misc-character-percent") <= value
			4:
				matches = _rng.draw(25, &"classic.misc-character-attribute") >= _character_attribute(character, absi(value))
			5:
				matches = _rng.draw(100, &"classic.misc-character-save") > character.save_value(absi(value))
			6:
				matches = not _game_state.selected_character_ids().is_empty() and _game_state.selected_character_ids()[0] == character.id
			7:
				matches = _character_has_classic_item(character, absi(value), true)
			8:
				matches = party.find(character) == value
		if matches:
			selected.append(character.id)
	_game_state.set_selected_character_ids(selected)
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected_by_rule", {"selector": selector, "value": value, "characterIds": selected})])


func _character_has_classic_item(character: CharacterState, classic_item_id: int, equipped_only: bool) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for instance: ItemInstance in character.inventory():
		if instance.definition_id == definition.id and (not equipped_only or instance.equipped):
			return true
	return false


static func _character_attribute(character: CharacterState, index: int) -> int:
	match index:
		0: return character.brawn
		1: return character.knowledge
		2: return character.judgment
		3: return character.agility
		4: return character.vitality
		5, 6: return character.luck
	return 0


func _start_battle(classic_battle_id: int, request_id: String, opcode: int) -> ScenarioRuntimeOperationResult:
	var battle := _content.battle_by_classic_id(absi(classic_battle_id))
	if battle == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Classic opcode %d references unavailable battle %d." % [opcode, classic_battle_id])
	return _start_battle_definition(battle, request_id, "classic")


func _start_battle_definition(battle: BattleDefinition, request_id: String, source: String) -> ScenarioRuntimeOperationResult:
	var result := _rules.combat_flow.start_battle(_game_state, _content, battle, _rng)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.completed:
		return ScenarioRuntimeOperationResult.completed(String(_game_state.last_battle_outcome), result.events)
	var continuation_kind := "safe-combat" if source == "scenario-action" else "classic-combat"
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": continuation_kind, "battleId": battle.id}, result.events)


func _resume_battle(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != &"combat_action" or not response.payload.get("actorId") is String or not response.payload.get("action") is String or response.payload.get("targetId", "") is not String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat response requires actorId, action, and optional targetId strings.")
	if _game_state.combat == null or _game_state.combat.battle_id != continuation.get("battleId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle is unavailable.")
	var result := _rules.combat_flow.submit_action(_game_state, _content, response.payload["actorId"], StringName(response.payload["action"]), response.payload.get("targetId", ""), _rng)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.completed:
		return ScenarioRuntimeOperationResult.completed(String(_game_state.last_battle_outcome), result.events)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, result.events)


func _combat_request(request_id: String) -> InteractionRequest:
	var combat := _game_state.combat
	var targets: Array[Dictionary] = []
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor:
			targets.append({"id": monster.id, "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health})
	return InteractionRequest.new(request_id, &"combat_action", {"battleId": combat.battle_id, "round": combat.round_number, "actorId": combat.active_actor_id(), "actions": ["attack", "defend", "retreat"], "targets": targets})


func _grant_treasure(classic_treasure_id: int) -> ScenarioRuntimeOperationResult:
	var treasure := _content.treasure_by_classic_id(absi(classic_treasure_id))
	if treasure == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Classic opcode 10 references unavailable treasure %d." % classic_treasure_id)
	return _grant_treasure_definition(treasure)


func _grant_treasure_definition(treasure: TreasureDefinition) -> ScenarioRuntimeOperationResult:
	var roll := _rules.economy.roll_treasure(treasure, _rng)
	_game_state.party.pooled_wealth.gold += roll.wealth.gold
	_game_state.party.pooled_wealth.gems += roll.wealth.gems
	_game_state.party.pooled_wealth.jewelry += roll.wealth.jewelry
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0:
			character.experience += roll.experience
	var granted_items: Array[String] = []
	var unclaimed_items: Array[String] = []
	for item_id: String in roll.item_ids:
		var item := _content.item_by_id(item_id)
		var granted := false
		if item != null:
			for character: CharacterState in _game_state.party.characters():
				var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("treasure.item"), true)
				if instance != null:
					granted_items.append(instance.id)
					granted = true
					break
		if not granted:
			unclaimed_items.append(item_id)
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"treasure_granted", {"treasureId": treasure.id, "experiencePerSurvivor": roll.experience, "gold": roll.wealth.gold, "gems": roll.wealth.gems, "jewelry": roll.wealth.jewelry, "itemInstanceIds": granted_items, "unclaimedItemIds": unclaimed_items})])


func _grant_item(character_id: String, item_id: String, identified: bool) -> ScenarioRuntimeOperationResult:
	var character := _game_state.party.character_by_id(character_id)
	var item := _content.item_by_id(item_id)
	if character == null or item == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item_target", "Grant Item references an unavailable character or item.")
	var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("scenario.item"), identified)
	if instance == null:
		return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The character cannot carry the granted item.")
	return ScenarioRuntimeOperationResult.completed(instance.id, [DomainEvent.new(&"item_granted", {"characterId": character.id, "itemId": item.id, "instanceId": instance.id, "identified": identified})])


func _apply_classic_condition(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 43 requires a five-value Extra Code row.")
	var target_mode := action.extra_code[0]
	var condition_index := action.extra_code[1]
	var duration := action.extra_code[2]
	if target_mode < 0 or target_mode > 2 or condition_index < 0 or condition_index >= ConditionSet.CHARACTER_COUNT:
		return ScenarioRuntimeOperationResult.failed(&"invalid_condition", "Classic opcode 43 has an invalid target or condition index.")
	var targets: Array[CharacterState] = []
	if target_mode == 1:
		targets = _game_state.selected_characters()
	else:
		for character: CharacterState in _game_state.party.characters():
			if target_mode == 0 or character.current_health > 0:
				targets.append(character)
	for character: CharacterState in targets:
		character.conditions.set_value(condition_index, duration)
	var ids: Array[String] = []
	for character: CharacterState in targets:
		ids.append(character.id)
	return ScenarioRuntimeOperationResult.completed(ids, [DomainEvent.new(&"condition_applied", {"characterIds": ids, "condition": condition_index, "duration": duration, "soundId": action.extra_code[3] if action.extra_code.size() > 3 else 0})])


func _remove_classic_ally(classic_monster_id: int) -> int:
	var definition := _content.monster_by_classic_id(classic_monster_id)
	return 0 if definition == null else _game_state.party.remove_allies_by_definition(definition.id)


func _add_classic_ally(classic_monster_id: int) -> ScenarioRuntimeOperationResult:
	var definition := _content.monster_by_classic_id(classic_monster_id)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 89 references unavailable monster %d." % classic_monster_id)
	var ally := _rules.monsters.build_monster(definition, _game_state.next_instance_id("party.ally"), 0, 0, _game_state.clock.day(), _rng)
	if ally == null or not _game_state.party.add_ally(ally):
		return ScenarioRuntimeOperationResult.failed(&"ally_add_failed", "The ally could not join the party.")
	return ScenarioRuntimeOperationResult.completed(ally.id, [DomainEvent.new(&"ally_added", {"allyId": ally.id, "monsterId": definition.id})])


func _deanimate_lower_undead() -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"no_active_battle", "Classic opcode 121 requires an active battle.")
	var affected: Array[String] = []
	for monster: MonsterState in _game_state.combat.monsters():
		var definition := _content.monster_by_id(monster.definition_id)
		if definition != null and definition.type_flag(1) and not definition.type_flag(5) and monster.current_health > 0:
			monster.current_health = 0
			affected.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(affected, [DomainEvent.new(&"lower_undead_deanimated", {"monsterIds": affected})])


func _spawn_classic_monsters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"no_active_battle", "Classic opcode 124 requires an active battle.")
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 124 requires a five-value Extra Code row.")
	var definition := _content.monster_by_classic_id(absi(action.extra_code[1]))
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 124 references unavailable monster %d." % action.extra_code[1])
	var authored_count := action.extra_code[2]
	var count := _rng.draw(absi(authored_count), &"classic.combat.spawn-count") if authored_count < 0 else authored_count
	var spawned: Array[String] = []
	for _index: int in maxi(0, count):
		var monster := _rules.monsters.build_monster(definition, _game_state.next_instance_id("combat.spawn"), -1, 0, _game_state.clock.day(), _rng)
		if monster != null and _game_state.combat.add_monster(monster):
			_game_state.combat.append_turn_actor(monster.id)
			spawned.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(spawned, [DomainEvent.new(&"combat_monsters_spawned", {"monsterId": definition.id, "instanceIds": spawned, "soundId": action.extra_code[3] if action.extra_code.size() > 3 else 0})])


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))
