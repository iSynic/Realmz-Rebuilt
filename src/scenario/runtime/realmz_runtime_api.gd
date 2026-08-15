class_name RealmzRuntimeApi
extends RefCounted

const SUPPORTED_SAFE_CAPABILITIES: Array[String] = [
	"core.combat.start",
	"core.economy.grant-treasure",
	"core.economy.take-gold",
	"core.inventory.grant-item",
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
var _battle_reward_operations: ClassicBattleRewardOperations
var _combat_operations: ClassicCombatOperations
var _control_flow_operations: ClassicControlFlowOperations
var _inventory_operations: ClassicInventoryOperations
var _service_operations: ClassicServiceOperations
var _presentation_operations: ClassicPresentationOpcodeHandler
var _world_time_operations: ClassicWorldTimeOpcodeHandler
var _encounter_operations: ClassicEncounterOpcodeHandler
var _classic_handlers: ClassicOpcodeHandlerRegistry
var _handler_registration_error: String = ""


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, action_state: ScenarioActionState, rules: RealmzRules = null) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_action_state = action_state
	_rules = rules if rules != null else RealmzRules.new()
	_character_operations = ClassicCharacterOperations.new(_content, _game_state, _rng, _rules)
	_battle_reward_operations = ClassicBattleRewardOperations.new(_content, _game_state, _rng, _rules)
	_battle_reward_operations.bind_runtime_api(self)
	_combat_operations = ClassicCombatOperations.new(_content, _game_state, _rules, _rng)
	_control_flow_operations = ClassicControlFlowOperations.new(_content, _game_state, _rng)
	_inventory_operations = ClassicInventoryOperations.new(_content, _game_state, _rules)
	_service_operations = ClassicServiceOperations.new(_content, _game_state, _rng, _rules)
	_presentation_operations = ClassicPresentationOpcodeHandler.new(_content, _game_state, _rng)
	_world_time_operations = ClassicWorldTimeOpcodeHandler.new(_content, _game_state, _rng)
	_encounter_operations = ClassicEncounterOpcodeHandler.new(_content, _game_state)
	_classic_handlers = ClassicOpcodeHandlerRegistry.new()
	for handler: ClassicOpcodeHandler in [_control_flow_operations, _character_operations, _inventory_operations, _service_operations, _combat_operations, _battle_reward_operations, _presentation_operations, _world_time_operations, _encounter_operations]:
		if not _classic_handlers.register(handler):
			_handler_registration_error = _classic_handlers.registration_error()
			break


func execute_classic(action: ClassicActionDefinition, request_id: String, context: Dictionary = {}) -> ScenarioRuntimeOperationResult:
	if not _handler_registration_error.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_opcode_registry", _handler_registration_error)
	if _classic_handlers.has_handler(action.opcode):
		return _classic_handlers.execute(action, request_id, context)
	return ScenarioRuntimeOperationResult.failed(&"unsupported_classic_opcode", "No Realmz Runtime API operation owns Classic opcode %d." % action.opcode)


func resolve_program_id(program_id: String) -> String:
	return _control_flow_operations.resolve_program_id(program_id)


func execute_safe(capability: String, arguments: Dictionary, request_id: String) -> ScenarioRuntimeOperationResult:
	match capability:
		"core.time.advance":
			if not _whole_number(arguments.get("minutes")) or int(arguments["minutes"]) < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Advance Time requires non-negative integer minutes.")
			return _with_age_update_interactions(ScenarioRuntimeOperationResult.completed(true, _rules.clock.advance_minutes(_game_state, _content, int(arguments["minutes"]))), request_id, ScenarioRuntimeContinuation.SAFE_AGE_UPDATES)
		"core.inventory.grant-item":
			if not arguments.get("characterId") is String or not arguments.get("itemId") is String or arguments.get("identified", false) is not bool:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Grant Item requires characterId, itemId, and optional identified bool.")
			return _battle_reward_operations.grant_item(arguments["characterId"], arguments["itemId"], arguments.get("identified", false))
		"core.economy.grant-treasure":
			if not arguments.get("treasureId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Grant Treasure requires a stable treasureId.")
			var treasure := _content.treasure_by_id(arguments["treasureId"])
			if treasure == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Treasure '%s' is unavailable." % arguments["treasureId"])
			return _battle_reward_operations.grant_treasure_definition(treasure, request_id)
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
			return _battle_reward_operations.start_battle_definition(battle, request_id, "scenario-action", ScenarioBattleCaller.safe_continue())
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
			var request := InteractionRequest.from_payload(request_id, &"scenario_choice", {"prompt": arguments["prompt"], "options": options})
			return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.safe_choice(options.size()))
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


func resume_safe(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String = "") -> ScenarioRuntimeOperationResult:
	if continuation == null or response == null or not response.is_supported_kind():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The response payload does not match its interaction kind.")
	match continuation.kind:
		ScenarioRuntimeContinuation.SAFE_AGE_UPDATES:
			return _resume_age_update_interactions(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.SAFE_CHOICE:
			var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
			var option_count: int = choice_continuation.option_count
			var choice := response.body as InteractionResponse.ChoiceBody
			if response.kind != &"scenario_choice" or choice == null or choice.index < 0 or choice.index >= option_count:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Scenario choice response must identify an available option.")
			return ScenarioRuntimeOperationResult.completed(choice.index)
		ScenarioRuntimeContinuation.SAFE_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE, ScenarioRuntimeContinuation.CLASSIC_REWARD:
			return _battle_reward_operations.resume(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Scenario Action interaction continuation is unavailable.")


func simple_encounter_by_id(encounter_id: int) -> SimpleEncounterDefinition:
	return _content.simple_encounter_by_id(encounter_id)


func write_action_state(state_scope: String, owner_id: String, name: String, value: Variant) -> bool:
	return _action_state.write(state_scope, owner_id, name, value)


func read_action_state(state_scope: String, owner_id: String, name: String, default_value: Variant = null) -> Variant:
	return _action_state.read(state_scope, owner_id, name, default_value)


func request_available_shop(request_id: String) -> ScenarioRuntimeOperationResult:
	var shop := _content.shop_by_id(_game_state.active_shop_id)
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"shop_unavailable", "No configured Classic shop is available at this location.")
	return _service_operations.request_shop_definition(shop, request_id, _game_state.shop_accept_ranges())


func request_available_temple(request_id: String) -> ScenarioRuntimeOperationResult:
	if not _game_state.temple_available:
		return ScenarioRuntimeOperationResult.failed(&"temple_unavailable", "No Classic temple is available at this location.")
	if _game_state.bank_available:
		_rules.economy.bank_to_pool(_game_state.party)
	var characters := _game_state.party.characters()
	var selected_character_id := "" if characters.is_empty() else characters[0].id
	var continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, _game_state.temple_cost_percent, _game_state.bank_available, selected_character_id)
	return ScenarioRuntimeOperationResult.waiting(_service_operations.temple_request(_game_state.temple_cost_percent, request_id, selected_character_id), continuation, [
		DomainEvent.new(&"temple_opened", {"costPercent": _game_state.temple_cost_percent, "bankAvailable": _game_state.bank_available}),
		DomainEvent.new(&"music_requested", {"musicId": 10, "source": "classic-temple"}),
		DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-temple-entry"}),
	])


func request_available_bank(request_id: String) -> ScenarioRuntimeOperationResult:
	if not _game_state.bank_available:
		return ScenarioRuntimeOperationResult.failed(&"bank_unavailable", "No Classic bank is available at this location.")
	return _request_banking(request_id)


static func party_defeat_handoff_is_valid(content: RealmzContent, state: GameState, handoff: ScenarioRuntimeHandoff) -> bool:
	return ClassicBattleRewardOperations.party_defeat_handoff_is_valid(content, state, handoff)


func complete_party_defeat_handoff(handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	return _battle_reward_operations.complete_party_defeat_handoff(handoff)


func begin_completed_battle_reward(request_id: String) -> ScenarioRuntimeOperationResult:
	return _battle_reward_operations.begin_completed_battle_reward(request_id)


func resume_classic(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if continuation == null or response == null or not response.is_supported_kind():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The response payload does not match its interaction kind.")
	match continuation.kind:
		ScenarioRuntimeContinuation.CLASSIC_AGE_UPDATES:
			return _resume_age_update_interactions(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER:
			return _resume_simple_encounter(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER:
			return _resume_complex_encounter(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_ACKNOWLEDGE:
			if response.kind != &"acknowledge":
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Acknowledgement response has the wrong kind.")
			return ScenarioRuntimeOperationResult.completed(true)
		ScenarioRuntimeContinuation.CLASSIC_TEXTBOX:
			var acknowledgement := response.body as InteractionResponse.AcknowledgeBody
			if response.kind != &"acknowledge" or acknowledgement == null:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic textbox response must acknowledge the displayed message.")
			if not acknowledgement.take_note:
				return ScenarioRuntimeOperationResult.completed(true)
			var message_id := (continuation.body as ScenarioRuntimeContinuation.TextBody).message_id
			if not GameState.journal_message_id_is_valid(message_id):
				return ScenarioRuntimeOperationResult.failed(&"journal_message_unrepresentable", "Classic message %d cannot be stored in the 3,000-entry journal flag table." % message_id)
			var already_recorded := _game_state.journal_message_is_recorded(message_id)
			if not _game_state.record_journal_message(message_id):
				return ScenarioRuntimeOperationResult.failed(&"journal_record_failed", "Classic message %d could not be recorded in the journal." % message_id)
			var events: Array[DomainEvent] = []
			if not already_recorded:
				events.append(DomainEvent.new(&"journal_entry_recorded", {"messageId": message_id}))
			return ScenarioRuntimeOperationResult.completed(true, events)
		ScenarioRuntimeContinuation.CLASSIC_PLAYER_MAP:
			var map_acknowledgement := response.body as InteractionResponse.AcknowledgeBody
			if response.kind != &"acknowledge" or map_acknowledgement == null or map_acknowledgement.take_note:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic player-map display requires an empty acknowledgement response.")
			var player_map_id := (continuation.body as ScenarioRuntimeContinuation.TextBody).player_map_id
			if _content.world.player_map_by_id(player_map_id) == null or not _game_state.world.has_map(player_map_id):
				return ScenarioRuntimeOperationResult.failed(&"invalid_vm_continuation", "Classic player-map continuation references unavailable acquired content.")
			return ScenarioRuntimeOperationResult.completed(true)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO, ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY, ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE, ScenarioRuntimeContinuation.CLASSIC_REWARD:
			return _battle_reward_operations.resume(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_CHARACTER_SELECTION:
			return _resume_character_selection(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_CHARACTER_ABILITY:
			return _resume_character_ability(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_CHOICE:
			return _resume_classic_choice(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_SHOP:
			return _resume_shop(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_TEMPLE:
			return _resume_temple(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT:
			return _resume_temple_exit(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_BANKING:
			return _resume_banking(continuation, response, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Classic interaction continuation is unavailable.")


func _with_age_update_interactions(operation: ScenarioRuntimeOperationResult, request_id: String, continuation_kind: StringName) -> ScenarioRuntimeOperationResult:
	if operation == null or operation.state != ScenarioRuntimeOperationResult.State.COMPLETED:
		return operation
	var updates := CharacterAgingResult.update_bodies(operation.events)
	if updates.is_empty():
		return operation
	var continuation := ScenarioRuntimeContinuation.age_updates(continuation_kind, updates, 1, operation.value, operation.directive)
	var events: Array[DomainEvent] = []
	events.assign(operation.events)
	events.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, updates[0]), continuation, events)


func _resume_age_update_interactions(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.AGE_UPDATE or not response.body is InteractionResponse.EmptyBody:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic age updates require an empty age-update acknowledgement.")
	var age := continuation.body as ScenarioRuntimeContinuation.AgeBody
	var updates := age.updates
	var index := age.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_continuation", "Classic age-update continuation is invalid.")
	var acknowledged: InteractionRequest.AgeUpdateBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: InteractionRequest.AgeUpdateBody = updates[index]
		var next_continuation := ScenarioRuntimeContinuation.age_updates(continuation.kind, updates, index + 1, age.value, age.directive)
		events.append(CharacterAgingResult.sound_event_for_update(next_payload))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, next_payload), next_continuation, events)
	return ScenarioRuntimeOperationResult.completed(age.value, events, age.directive)


func _resume_simple_encounter(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
	var encounter := _content.simple_encounter_by_id(choice_continuation.encounter_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Simple Encounter is unavailable.")
	var choice := response.body as InteractionResponse.ChoiceBody
	if response.kind != &"encounter_choice" or choice == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response has the wrong kind.")
	if choice.cancelled:
		if not encounter.can_back_out:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Simple Encounter cannot be cancelled.")
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "simple", "encounterId": encounter.id})], ScenarioVmDirective.finish())
	var selected_index := choice.index
	var option_indexes := choice_continuation.option_indexes
	if not option_indexes.is_empty():
		if selected_index < 0 or selected_index >= option_indexes.size() or not _whole_number(option_indexes[selected_index]):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the available choices.")
		selected_index = int(option_indexes[selected_index])
	var selected := encounter.response_at(selected_index)
	if selected == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the authored choices.")
	_game_state.record_encounter_attempt(&"simple", encounter.id)
	return ScenarioRuntimeOperationResult.completed(selected.id, [DomainEvent.new(&"encounter_response_selected", {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index})], ScenarioVmDirective.branch_program(selected.result_program_id, choice_continuation.gosub, {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index}))


func _resume_complex_encounter(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
	var encounter := _content.complex_encounter_by_id(choice_continuation.encounter_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Complex Encounter is unavailable.")
	var selection := response.body as InteractionResponse.ComplexEncounterBody
	if response.kind != &"complex_encounter" or selection == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex Encounter response requires an action.")
	var action := String(selection.action)
	var outcome := 0
	var context: Dictionary = {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": action}
	var events: Array[DomainEvent] = []
	match action:
		"back":
			if not encounter.can_back_out:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Complex Encounter cannot be cancelled.")
			return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "complex", "encounterId": encounter.id})], ScenarioVmDirective.finish())
		"choice":
			if selection.slot < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action response requires an authored slot.")
			var slot := selection.slot
			var labels := encounter.action_labels()
			if slot < 0 or slot >= labels.size() or labels[slot].strip_edges() in ["", "*"]:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action slot is unavailable.")
			outcome = encounter.action_result
			context["optionSlot"] = slot
		"word":
			if selection.word.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex word response requires text.")
			outcome = _complex_word_outcome(encounter, selection.word)
		"spell":
			if selection.classic_spell_id == 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex spell response requires a Classic spell ID.")
			outcome = _complex_catalog_outcome(encounter.spell_ids(), encounter.spell_results(), selection.classic_spell_id)
		"item":
			if selection.classic_item_id == 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex item response requires a Classic item ID.")
			var item_id := selection.classic_item_id
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
	return _complex_outcome(encounter, outcome, choice_continuation.gosub, context, events)


func _complex_outcome(encounter: ComplexEncounterDefinition, outcome: int, gosub: bool, context: Dictionary, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var program_id := encounter.result_program_id(outcome)
	if program_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Complex Encounter result is outside 1 through 4.")
	return ScenarioRuntimeOperationResult.completed(outcome, events, ScenarioVmDirective.branch_program(program_id, gosub, context))


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


func _resume_thief_encounter(encounter: ComplexEncounterDefinition, continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var thief_encounter := _content.thief_encounter_by_id(encounter.thief_success)
	var selection := response.body as InteractionResponse.ComplexEncounterBody
	if thief_encounter == null or selection == null or selection.action_index < 0 or selection.character_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter response requires an available action and character.")
	var character := _game_state.party.character_by_id(selection.character_id)
	var action_index := selection.action_index
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
	var chance := clampi(character.ability_value(action_index) + modifiers[action_index], 0, 100)
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
		var request := _encounter_operations.complex_encounter_request(encounter, request_id)
		if request == null:
			return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter has no available responses after the Thief action.")
		return ScenarioRuntimeOperationResult.waiting(request, continuation, events)
	if outcome < 1 or outcome > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Thief Encounter produced invalid result %d." % outcome)
	_game_state.record_encounter_attempt(&"complex", encounter.id)
	return _complex_outcome(encounter, outcome, (continuation.body as ScenarioRuntimeContinuation.ChoiceBody).gosub, {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": "thief", "actionIndex": action_index, "characterId": character.id}, events)


func _spring_thief_trap(encounter: ComplexEncounterDefinition, thief_encounter: ThiefEncounterDefinition, continuation: ScenarioRuntimeContinuation, character: CharacterState, flags: Array[bool], request_id: String) -> ScenarioRuntimeOperationResult:
	flags[9] = false
	flags[1] = false
	flags[6] = true
	_game_state.set_thief_encounter_type_flags(thief_encounter, flags)
	var damage := _rng.draw_between(thief_encounter.low_damage, thief_encounter.high_damage, &"classic.thief-trap-damage") if thief_encounter.high_damage >= thief_encounter.low_damage and thief_encounter.high_damage > 0 else 0
	if damage > 0:
		character.current_health = maxi(-32_768, character.current_health - damage)
	var events: Array[DomainEvent] = [DomainEvent.new(&"thief_trap_sprung", {"encounterId": encounter.id, "thiefEncounterId": thief_encounter.id, "characterId": character.id, "damage": damage, "spellId": thief_encounter.spell_id})]
	var request := _encounter_operations.complex_encounter_request(encounter, request_id)
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


func _resume_classic_choice(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != &"yes_no" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic choice response requires an accepted bool.")
	var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
	var values := choice_continuation.values
	if values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_vm_continuation", "Classic choice continuation is malformed.")
	var apply_result: bool = body.accepted != (int(values[0]) != 0)
	if not apply_result:
		return ScenarioRuntimeOperationResult.completed(false)
	match int(values[1]):
		0:
			return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.finish())
		1:
			return _branch_xap(int(values[2]), choice_continuation.gosub)
		4:
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_elimination_requested")])
	return ScenarioRuntimeOperationResult.failed(&"unsupported_choice_target", "Classic choice branch mode %d is not available." % int(values[1]))


func _resume_character_selection(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != &"character_selection" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection response requires characterIds.")
	var character_continuation := continuation.body as ScenarioRuntimeContinuation.CharacterBody
	var requested: Array[String] = body.character_ids
	if requested.size() != character_continuation.count:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection returned the wrong number of characters.")
	var picked: Array[String] = []
	for value: Variant in requested:
		if not value is String or picked.has(value):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection contains an invalid or duplicate ID.")
		var character := _game_state.party.character_by_id(value)
		if character == null or not character_continuation.allow_dead and character.current_health <= 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection includes an ineligible party member.")
		picked.append(value)
	var selected := picked
	if character_continuation.invert:
		selected = []
		for character: CharacterState in _game_state.party.characters():
			if not picked.has(character.id):
				selected.append(character.id)
	if not _game_state.set_selected_character_ids(selected):
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_selection", "Selected character state rejected the response.")
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected", {"characterIds": selected, "inverted": character_continuation.invert})])


func _resume_character_ability(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != &"character_selection" or body == null or body.character_ids.size() != 1:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check requires one selected character.")
	var character := _game_state.party.character_by_id(body.character_ids[0])
	var character_continuation := continuation.body as ScenarioRuntimeContinuation.CharacterBody
	var values := character_continuation.values
	if character == null or character.current_health <= 0 or values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check selected an unavailable character.")
	_game_state.set_selected_character_ids([character.id])
	var check_index := int(values[0])
	var modifier := int(values[1])
	var attribute_check := int(values[2]) != 0
	var roll := _rng.draw(25 if attribute_check else 100, &"classic.character-ability")
	if attribute_check and check_index not in [0, 1, 2, 3, 4, 6]:
		var inert_event := DomainEvent.new(&"character_ability_checked", {"characterId": character.id, "checkIndex": check_index, "attribute": true, "modifier": modifier, "roll": roll, "branch": "none", "sourceDefined": false})
		return ScenarioRuntimeOperationResult.completed(character.id, [inert_event])
	var check_value := _character_attribute(character, check_index) if attribute_check else character.ability_value(check_index)
	var passed := roll - modifier < check_value if attribute_check else roll <= check_value + modifier
	var target_id := int(values[3] if passed else values[4])
	var event := DomainEvent.new(&"character_ability_checked", {"characterId": character.id, "checkIndex": check_index, "attribute": attribute_check, "value": check_value, "modifier": modifier, "roll": roll, "passed": passed})
	var branch := _branch_xap(target_id, character_continuation.gosub)
	branch.events.append(event)
	return branch


func _party_has_classic_item(classic_item_id: int, minimum_charges: int = -1, equipped_only: bool = false) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in _game_state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id == definition.id and (minimum_charges < 0 or instance.charges >= minimum_charges) and (not equipped_only or instance.equipped):
				return true
	return false


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(false)
	return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_xap(target_id, gosub))


func _resume_shop(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.ShopBody
	if response.kind != &"shop_action" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop response requires an action string.")
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var shop := _content.shop_by_id(service.shop_id)
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "The pending shop is unavailable.")
	var operation := String(body.action)
	if operation == "leave":
		if _game_state.bank_available:
			_rules.economy.pool_to_bank(_game_state.party)
		return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_closed", {"shopId": shop.id, "pooledWealthReturnedToBank": _game_state.bank_available})])
	var events: Array[DomainEvent] = []
	match operation:
		"buy":
			if body.character_id.is_empty() or body.stock_key.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop buy requires stock identity and characterId.")
			var stock_entry := _service_operations.resolve_shop_stock(shop, body.stock_key)
			if stock_entry == null or stock_entry.quantity < 1:
				return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "The selected shop item is out of stock.")
			var character := _game_state.party.character_by_id(body.character_id)
			var item := stock_entry.item
			if character == null or item == null or character.inventory().size() >= InventoryRules.MAX_ITEMS or character.carried_load + item.instance_weight(item.initial_charges) > character.maximum_load:
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The selected character cannot carry this item.")
			var price := _rules.economy.shop_buy_price(item, _game_state.shop_inflation(shop))
			if not _rules.economy.take(_game_state.party, price, WealthState.Kind.GOLD):
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "The party cannot afford this item.")
			var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("shop.item"), true)
			if instance == null:
				_game_state.party.pooled_wealth.gold += price
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The item could not be added after purchase validation.")
			if stock_entry.kind == &"base":
				var stock_index := stock_entry.index
				_game_state.set_shop_quantity(shop, stock_index, _game_state.shop_quantity(shop, stock_index) - 1)
			else:
				_game_state.set_shop_buyback_quantity(shop.id, item.id, stock_entry.quantity - 1)
			events.append(DomainEvent.new(&"shop_item_bought", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		"sell":
			if body.character_id.is_empty() or body.instance_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop sell requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(body.character_id)
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The shop sale character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == body.instance_id:
					instance = candidate
					break
			if instance == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item_instance", "The sold item instance is unavailable.")
			var item := _content.item_by_id(instance.definition_id)
			if item == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item", "The sold item definition is unavailable.")
			if instance.equipped:
				return ScenarioRuntimeOperationResult.failed(&"equipped_item", "Unequip this item before selling it.")
			var accept_ranges: Array[int] = []
			accept_ranges.assign(service.accept_ranges)
			if not ClassicServiceOperations.shop_accepts_item(item, accept_ranges):
				return ScenarioRuntimeOperationResult.failed(&"shop_rejects_item", "This shop does not accept the selected item.")
			var price := _rules.economy.shop_sell_price(item, instance, _game_state.shop_inflation(shop))
			if _rules.inventory.remove_item(character, instance.id, item) == null:
				return ScenarioRuntimeOperationResult.failed(&"shop_sale_failed", "The selected item could not be removed.")
			_game_state.party.pooled_wealth.gold += price
			var base_index := shop.item_ids().find(item.id)
			if base_index >= 0:
				_game_state.set_shop_quantity(shop, base_index, _game_state.shop_quantity(shop, base_index) + 1)
			else:
				_game_state.set_shop_buyback_quantity(shop.id, item.id, _game_state.shop_buyback_quantity(shop.id, item.id) + 1)
			events.append(DomainEvent.new(&"shop_item_sold", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		"identify":
			if body.character_id.is_empty() or body.instance_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop identification requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(body.character_id)
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The identification character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == body.instance_id:
					instance = candidate
					break
			if instance == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item_instance", "The identification item is unavailable.")
			if instance.identified:
				return ScenarioRuntimeOperationResult.failed(&"already_identified", "This item is already identified.")
			if not _rules.economy.take(_game_state.party, 20, WealthState.Kind.GOLD):
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "Identification costs 20 gold.")
			instance.identified = true
			events.append(DomainEvent.new(&"item_identified", {"shopId": shop.id, "instanceId": instance.id, "characterId": character.id, "price": 20, "source": "classic-shop"}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 683, "waitForCompletion": false, "source": "classic-shop-identify"}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_shop_action", "Shop action '%s' is unavailable." % operation)
	var ranges: Array[int] = []
	ranges.assign(service.accept_ranges)
	return ScenarioRuntimeOperationResult.waiting(_service_operations.shop_request(shop, request_id, ranges), continuation, events)


func _resume_temple(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.TempleBody
	if response.kind != InteractionRequest.TEMPLE or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple response requires an action.")
	var operation := String(body.action)
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var cost_percent := service.cost_percent
	var selected_character_id := service.selected_character_id
	if not body.character_id.is_empty():
		if _game_state.party.character_by_id(body.character_id) == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected temple character is unavailable.")
		selected_character_id = body.character_id
	var next_continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, cost_percent, service.bank_available, selected_character_id)
	match operation:
		"leave":
			if service.bank_available:
				_rules.economy.pool_to_bank(_game_state.party)
				return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": true})])
			if _has_pooled_wealth():
				var prompt := "Pooled wealth remains. Return to the temple to distribute it before leaving?"
				var request := InteractionRequest.yes_no(request_id, prompt, "Return", "Leave it behind")
				return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT, cost_percent, false, selected_character_id))
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": false})])
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var pool_probe := _rules.economy.pool_probe(_game_state.party)
			if not pool_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", pool_probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			return ScenarioRuntimeOperationResult.waiting(_service_operations.temple_request(cost_percent, request_id, selected_character_id), next_continuation, [
				DomainEvent.new(&"wealth_pooled", {"source": "classic-temple"}),
				DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-temple-pool"}),
			])
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var share_probe := _rules.economy.share_probe(_game_state.party)
			if not share_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", share_probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			return ScenarioRuntimeOperationResult.waiting(_service_operations.temple_request(cost_percent, request_id, selected_character_id), next_continuation, [
				DomainEvent.new(&"wealth_shared", {"source": "classic-temple", "remaining": _game_state.party.pooled_wealth.to_data()}),
				DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-temple-share"}),
			])
		"service":
			return _apply_temple_service(next_continuation, body, request_id)
	return ScenarioRuntimeOperationResult.failed(&"unknown_temple_action", "Temple action '%s' is unavailable." % operation)


func _apply_temple_service(continuation: ScenarioRuntimeContinuation, body: InteractionResponse.TempleBody, request_id: String) -> ScenarioRuntimeOperationResult:
	if body.character_id.is_empty() or body.service_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple service requires characterId and serviceId.")
	var character := _game_state.party.character_by_id(body.character_id)
	var service_id := StringName(body.service_id)
	if character == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_character", "Temple service target is unavailable.")
	if not TempleRules.SERVICE_IDS.has(service_id):
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var cost := _rules.temple.service_cost(service_id, service.cost_percent)
	var next_continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, service.cost_percent, service.bank_available, character.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 10129, "waitForCompletion": false, "source": "classic-temple-service"})]
	if cost > _game_state.party.pooled_wealth.gold + character.money.gold:
		events.append(DomainEvent.new(&"temple_service_rejected", {"serviceId": String(service_id), "characterId": character.id, "cost": cost, "reason": "insufficient_gold"}))
		return ScenarioRuntimeOperationResult.waiting(_service_operations.temple_request(service.cost_percent, request_id, character.id), next_continuation, events)
	if not _rules.economy.take_from_pool_and_character(_game_state.party, character, cost, WealthState.Kind.GOLD):
		return ScenarioRuntimeOperationResult.failed(&"temple_payment_failed", "Temple payment could not be committed after affordability validation.")
	var result := _rules.temple.apply_service(character, service_id, _rng, _content.item_definitions())
	if result == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	events.append(DomainEvent.new(&"temple_service_completed", result.to_event_data(character.id, cost)))
	return ScenarioRuntimeOperationResult.waiting(_service_operations.temple_request(service.cost_percent, request_id, character.id), next_continuation, events)


func _resume_temple_exit(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple exit requires a yes/no response.")
	if body.accepted:
		var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
		return ScenarioRuntimeOperationResult.waiting(
			_service_operations.temple_request(service.cost_percent, request_id, service.selected_character_id),
			ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, service.cost_percent, false, service.selected_character_id),
			[DomainEvent.new(&"temple_exit_cancelled", {"reason": "pooled_wealth"})]
		)
	var discarded := _game_state.party.pooled_wealth.to_data()
	_game_state.party.pooled_wealth = WealthState.new()
	return ScenarioRuntimeOperationResult.completed(true, [
		DomainEvent.new(&"pooled_wealth_discarded", {"source": "classic-temple-exit", "wealth": discarded}),
		DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": false}),
	])


func _has_pooled_wealth() -> bool:
	return _game_state.party.pooled_wealth.gold != 0 or _game_state.party.pooled_wealth.gems != 0 or _game_state.party.pooled_wealth.jewelry != 0


func _request_banking(request_id: String) -> ScenarioRuntimeOperationResult:
	_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id), ScenarioRuntimeContinuation.banking(), [
		DomainEvent.new(&"bank_opened", {"pooledWealth": _game_state.party.pooled_wealth.to_data()}),
		DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-button"}),
		DomainEvent.new(&"sound_requested", {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "source": "classic-bank-swap-open"}),
	])


func _bank_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var characters: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		var transfers: Array[Dictionary] = []
		for denomination: String in ["gold", "gems", "jewelry"]:
			var kind := _wealth_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, true)
			transfers.append({
				"denomination": denomination,
				"amount": amount,
				"toPool": _economy_probe_data(to_pool),
				"toCharacter": _economy_probe_data(to_character),
			})
		characters.append({
			"id": character.id,
			"name": character.name,
			"wealth": character.money.to_data(),
			"load": character.carried_load,
			"maximumLoad": character.maximum_load,
			"transfers": transfers,
		})
	if selected_character_id.is_empty() and not characters.is_empty():
		selected_character_id = String(characters[0]["id"])
	return InteractionRequest.from_payload(request_id, InteractionRequest.BANK, {
		"selectedCharacterId": selected_character_id,
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankedWealth": _game_state.party.banked_wealth.to_data(),
		"pool": _economy_probe_data(_rules.economy.pool_probe(_game_state.party)),
		"share": _economy_probe_data(_rules.economy.share_probe(_game_state.party)),
		"characters": characters,
		"actions": ["pool", "share", "to-pool", "to-character", "leave"],
	})


func _resume_banking(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.BankBody
	if response.kind != InteractionRequest.BANK or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank response requires an action.")
	var action := String(body.action)
	if action == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [
			DomainEvent.new(&"bank_closed", {"pooledWealthReturnedToBank": false}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-done"}),
		])
	var selected_character_id := body.character_id
	var events: Array[DomainEvent] = []
	match action:
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var probe := _rules.economy.pool_probe(_game_state.party)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-bank", "wealth": _game_state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-pool"}))
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var probe := _rules.economy.share_probe(_game_state.party)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-bank", "remaining": _game_state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-share"}))
		"to-pool", "to-character":
			if body.character_id.is_empty() or body.denomination.is_empty() or body.amount < 1:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank-backed Swap requires character, denomination, and amount.")
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var character := _game_state.party.character_by_id(body.character_id)
			var kind := _wealth_kind(body.denomination)
			var amount := body.amount
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected bank character is unavailable.")
			if kind < 0:
				return ScenarioRuntimeOperationResult.failed(&"unknown_wealth_kind", "The selected bank denomination is unavailable.")
			if amount != EconomyRules.classic_transfer_increment(kind as WealthState.Kind):
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character := action == "to-character"
			var probe := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, to_character)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			var transferred := _rules.economy.transfer_pool_to_character(_game_state.party, character, kind as WealthState.Kind, amount) if to_character else _rules.economy.transfer_character_to_pool(_game_state.party, character, kind as WealthState.Kind, amount)
			if not transferred:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", "The selected bank transfer is no longer available.")
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-bank", "characterId": character.id, "direction": action, "kind": body.denomination, "amount": amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-bank-swap"}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_bank_action", "Bank action '%s' is unavailable." % action)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id, selected_character_id), continuation, events)


static func _economy_probe_data(probe: EconomyActionProbe) -> Dictionary:
	return {"enabled": probe != null and probe.allowed, "reason": "" if probe != null and probe.allowed else "Action availability is unavailable." if probe == null else probe.reason}


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


static func _wealth_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1


func _money_movement_context_error() -> String:
	for character: CharacterState in _game_state.party.characters():
		if _content.race_by_id(character.race_id) == null or _content.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


func _recalculate_party_movement() -> void:
	for character: CharacterState in _game_state.party.characters():
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		_rules.characters.recalculate_movement(character, race, caste.movement_bonus)


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))
