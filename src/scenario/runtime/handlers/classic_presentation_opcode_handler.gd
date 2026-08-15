class_name ClassicPresentationOpcodeHandler
extends ClassicOpcodeHandler

var _content: RealmzContent
var _rng: RealmzRng


func _init(content: RealmzContent, rng: RealmzRng) -> void:
	_content = content
	_rng = rng


func opcode_ids() -> Array[int]:
	return [9, 19, 27, 28, 62]


func execute(action: ClassicActionDefinition, _request_id: String, _context: Dictionary) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		9:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"sound_requested", {
				"soundId": absi(action.operand_id),
				"waitForCompletion": action.operand_id < 0,
				"source": "classic",
			})])
		19:
			return _show_random_message(action)
		27:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"picture_requested", {
				"pictureId": absi(action.operand_id),
				"source": "classic",
			})])
		28:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"map_redraw_requested", {"source": "classic"})])
		62:
			var scrolling_message := _content.message_by_id(absi(action.operand_id))
			if scrolling_message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 62 references unavailable scrolling text %d." % action.operand_id)
			return ScenarioRuntimeOperationResult.completed(scrolling_message.id, [DomainEvent.new(&"scrolling_text_requested", {
				"messageId": scrolling_message.id,
				"text": scrolling_message.text,
				"source": "classic",
			})])
	return super.execute(action, _request_id, _context)


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
	var message := _content.message_by_id(selected_id)
	return ScenarioRuntimeOperationResult.completed(selected_id, [DomainEvent.new(&"message_shown", {
		"messageId": selected_id,
		"text": message.text,
		"source": "classic-random",
	})])
