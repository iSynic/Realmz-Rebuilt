class_name RealmzRuntimeApi
extends RefCounted

const SUPPORTED_SAFE_CAPABILITIES: Array[String] = [
	"core.presentation.choice",
	"core.presentation.text",
	"core.state.read",
	"core.state.write",
]

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _action_state: ScenarioActionState


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, action_state: ScenarioActionState) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_action_state = action_state


func execute_classic(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		1:
			var message := _content.message_by_id(action.operand_id)
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 1 references unavailable message %d." % action.operand_id)
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new("message_shown", {"messageId": action.operand_id, "text": message.text, "source": "classic"})])
		4:
			var encounter := _content.simple_encounter_by_id(action.operand_id)
			if encounter == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "Classic opcode 4 references unavailable Simple Encounter %d." % action.operand_id)
			var prompt := _content.message_by_id(encounter.prompt_message_id)
			if prompt == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
			var options: Array[Dictionary] = []
			for response: SimpleEncounterResponse in encounter.responses():
				options.append({"id": response.id, "label": response.label})
			var request := InteractionRequest.new(request_id, &"encounter_choice", {"encounterKind": "simple", "encounterId": encounter.id, "prompt": prompt.text, "options": options, "canBackOut": encounter.can_back_out})
			return ScenarioRuntimeOperationResult.waiting(request, {"kind": "simple-encounter", "encounterId": encounter.id, "gosub": action.gosub})
		_:
			return ScenarioRuntimeOperationResult.failed(&"unsupported_classic_opcode", "No Realmz Runtime API operation owns Classic opcode %d." % action.opcode)


func execute_safe(capability: String, arguments: Dictionary, request_id: String) -> ScenarioRuntimeOperationResult:
	match capability:
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


func resume_safe(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	match continuation.get("kind"):
		"safe-choice":
			var option_count: int = int(continuation.get("optionCount", 0))
			if response.kind != &"scenario_choice" or not response.payload.get("index") is int or response.payload["index"] < 0 or response.payload["index"] >= option_count:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Scenario choice response must identify an available option.")
			return ScenarioRuntimeOperationResult.completed(response.payload["index"])
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Scenario Action interaction continuation is unavailable.")


func simple_encounter_by_id(encounter_id: int) -> SimpleEncounterDefinition:
	return _content.simple_encounter_by_id(encounter_id)


func write_action_state(state_scope: String, owner_id: String, name: String, value: Variant) -> bool:
	return _action_state.write(state_scope, owner_id, name, value)


func read_action_state(state_scope: String, owner_id: String, name: String, default_value: Variant = null) -> Variant:
	return _action_state.read(state_scope, owner_id, name, default_value)


func _state_identity(arguments: Dictionary) -> Array[String]:
	var state_scope := str(arguments.get("scope", "campaign"))
	var owner_id := str(arguments.get("ownerId", ""))
	var name_value: Variant = arguments.get("name", arguments.get("id"))
	if state_scope.is_empty() or name_value == null or (not name_value is String and not name_value is int):
		return []
	return [state_scope, owner_id, str(name_value)]
