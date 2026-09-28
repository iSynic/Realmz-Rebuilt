## Executes the Classic presentation opcode handler family of validated Classic instructions.

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
				ScenarioInteractionContinuations.acknowledge(),
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
			if _content.requires_deferred_references and not _content.has_media_resource("TEXT", action.operand_id):
				return ScenarioRuntimeOperationResult.failed(&"unknown_media_resource", "Classic opcode 62 references unavailable TEXT resource %d." % action.operand_id)
			return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {
				"prompt": "",
				"presentation": "classic-scrolling-text",
				"resourceType": "TEXT",
				"resourceId": action.operand_id,
			}), ScenarioInteractionContinuations.acknowledge(), [DomainEvent.new(&"scrolling_text_requested", {
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
			return _set_dungeon_multiview(action.opcode == 97)
	return super.execute(action, request_id, context)


func _set_dungeon_multiview(enabled: bool) -> ScenarioRuntimeOperationResult:
	var changed := _game_state.dungeon_multiview != enabled
	_game_state.dungeon_multiview = enabled
	var events: Array[DomainEvent] = [DomainEvent.new(&"dungeon_view_policy_changed", {"multiview": enabled, "source": "classic"})]
	# Castle newland.c warns only on transitions; warn.c uses STR# 3:96/97 and sound 6000.
	if changed:
		events.append(DomainEvent.new(&"classic_notification_requested", {
			"text": "You may now use the 3D or look down view." if enabled else "You may now use the 3D view only.",
			"soundId": 6000,
			"source": "classic-opcode-%d" % (97 if enabled else 96),
		}))
	return ScenarioRuntimeOperationResult.completed(enabled, events)


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
	var message := _content.scenario_records.message_by_id(message_id)
	if message == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 1 references unavailable message %d." % action.operand_id)
	var event := DomainEvent.new(&"message_shown", {"messageId": message_id, "text": message.text, "source": "classic", "classicClick": action.operand_id > 0})
	if action.operand_id <= 0:
		return ScenarioRuntimeOperationResult.completed(null, [event])
	var journal_eligible := ScenarioProgressState.journal_message_id_is_valid(message_id)
	var request := InteractionRequest.from_payload(request_id, &"acknowledge", {
		"prompt": message.text,
		"messageId": message_id,
		"presentation": "classic-textbox",
		"journalEligible": journal_eligible,
		"journalRecorded": journal_eligible and _game_state.scenario_progress.journal_message_is_recorded(message_id),
	})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioInteractionContinuations.textbox(message_id), [event])


func _show_random_message(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var low_id := action.extra_code[0] if action.extra_code.size() > 0 else action.operand_id
	var high_id := action.extra_code[1] if action.extra_code.size() > 1 else low_id
	var selected_id := _rng.draw_between_classic(low_id, high_id, &"classic.random-message")
	if selected_id == 0:
		return ScenarioRuntimeOperationResult.completed(selected_id)
	var message_id := absi(selected_id)
	var message := _content.scenario_records.message_by_id(message_id)
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
	var journal_eligible := ScenarioProgressState.journal_message_id_is_valid(message_id)
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {
		"prompt": message.text,
		"messageId": message_id,
		"presentation": "classic-textbox",
		"journalEligible": journal_eligible,
		"journalRecorded": journal_eligible and _game_state.scenario_progress.journal_message_is_recorded(message_id),
	}), ScenarioInteractionContinuations.textbox(message_id), [event])
