class_name ClassicPresentationOpcodeHandler
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng) -> void:
	_content = content
	_game_state = game_state
	_rng = rng


func opcode_ids() -> Array[int]:
	return [1, 9, 19, 26, 27, 28, 62, 71, 93, 94, 96, 97]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		1:
			return _show_message(action, request_id)
		9:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"sound_requested", {
				"soundId": absi(action.operand_id),
				"waitForCompletion": action.operand_id < 0,
				"source": "classic",
			})])
		19:
			return _show_random_message(action, request_id)
		26:
			return ScenarioRuntimeOperationResult.waiting(
				InteractionRequest.from_payload(request_id, &"acknowledge", {"prompt": "Continue", "presentation": "classic-click-modal"}),
				ScenarioRuntimeContinuation.empty(ScenarioRuntimeContinuation.CLASSIC_ACKNOWLEDGE),
				[DomainEvent.new(&"sound_requested", {"soundId": 30005, "waitForCompletion": false, "source": "classic-opcode-26"})]
			)
		27:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"picture_requested", {
				"pictureId": absi(action.operand_id),
				"source": "classic",
			})])
		28:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"map_redraw_requested", {"source": "classic"})])
		62:
			return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {
				"prompt": "",
				"presentation": "classic-scrolling-text",
				"resourceType": "TEXT",
				"resourceId": action.operand_id,
			}), ScenarioRuntimeContinuation.empty(ScenarioRuntimeContinuation.CLASSIC_ACKNOWLEDGE), [DomainEvent.new(&"scrolling_text_requested", {
				"resourceType": "TEXT",
				"resourceId": action.operand_id,
				"source": "classic",
			})])
		71:
			_game_state.xy_display_hidden = action.operand_id != 0
			return ScenarioRuntimeOperationResult.completed(_game_state.xy_display_hidden, [DomainEvent.new(&"coordinate_display_changed", {"hidden": _game_state.xy_display_hidden, "source": "classic"}), DomainEvent.new(&"map_redraw_requested", {"source": "classic-opcode-71"})])
		93, 94:
			return _set_compass_enabled(action.opcode == 93)
		96, 97:
			_game_state.dungeon_multiview = action.opcode == 97
			return ScenarioRuntimeOperationResult.completed(_game_state.dungeon_multiview, [DomainEvent.new(&"dungeon_view_policy_changed", {"multiview": _game_state.dungeon_multiview, "source": "classic"})])
	return super.execute(action, request_id, context)


func _set_compass_enabled(enabled: bool) -> ScenarioRuntimeOperationResult:
	var events: Array[DomainEvent] = []
	if _game_state.compass_enabled == enabled:
		events.append(DomainEvent.new(&"message_shown", {"messageId": 98 if enabled else 99, "text": "The compass is already enabled." if enabled else "The compass is already disabled.", "source": "classic-warning"}))
	_game_state.compass_enabled = enabled
	events.append(DomainEvent.new(&"compass_visibility_changed", {"enabled": enabled, "source": "classic"}))
	events.append(DomainEvent.new(&"map_redraw_requested", {"source": "classic-compass"}))
	return ScenarioRuntimeOperationResult.completed(enabled, events)


func _show_message(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var message_id := absi(action.operand_id)
	var message := _content.message_by_id(message_id)
	if message == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 1 references unavailable message %d." % action.operand_id)
	var event := DomainEvent.new(&"message_shown", {"messageId": message_id, "text": message.text, "source": "classic", "classicClick": action.operand_id > 0})
	if action.operand_id <= 0:
		return ScenarioRuntimeOperationResult.completed(null, [event])
	var journal_eligible := GameState.journal_message_id_is_valid(message_id)
	var request := InteractionRequest.from_payload(request_id, &"acknowledge", {
		"prompt": message.text,
		"messageId": message_id,
		"presentation": "classic-textbox",
		"journalEligible": journal_eligible,
		"journalRecorded": journal_eligible and _game_state.journal_message_is_recorded(message_id),
	})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.textbox(message_id), [event])


func _show_random_message(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var low_id := action.extra_code[0] if action.extra_code.size() > 0 else action.operand_id
	var high_id := action.extra_code[1] if action.extra_code.size() > 1 else low_id
	var selected_id := _rng.draw_between_classic(low_id, high_id, &"classic.random-message")
	if selected_id == 0:
		return ScenarioRuntimeOperationResult.completed(selected_id)
	var message_id := absi(selected_id)
	var message := _content.message_by_id(message_id)
	if message == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 19 has no available message.")
	var event := DomainEvent.new(&"message_shown", {
		"messageId": message_id,
		"text": message.text,
		"source": "classic-random",
		"classicClick": selected_id > 0,
	})
	if selected_id < 0:
		return ScenarioRuntimeOperationResult.completed(selected_id, [event])
	var journal_eligible := GameState.journal_message_id_is_valid(message_id)
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {
		"prompt": message.text,
		"messageId": message_id,
		"presentation": "classic-textbox",
		"journalEligible": journal_eligible,
		"journalRecorded": journal_eligible and _game_state.journal_message_is_recorded(message_id),
	}), ScenarioRuntimeContinuation.textbox(message_id), [event])
