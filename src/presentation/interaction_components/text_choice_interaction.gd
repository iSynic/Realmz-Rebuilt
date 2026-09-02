class_name TextChoiceInteraction
extends InteractionComponent

var _autojournal_enabled: bool = false
var _manual_journal_available: bool = false
var _acknowledgement_body: InteractionResponse.AcknowledgeBody


func configure(autojournal_enabled: bool) -> void:
	_autojournal_enabled = autojournal_enabled


func build(request: InteractionRequest) -> void:
	_manual_journal_available = false
	_acknowledgement_body = null
	match request.kind:
		&"encounter_choice", &"scenario_choice":
			var body := request.body as InteractionRequest.ChoiceRequestBody
			if body == null: return
			var grid := _choice_grid(1, true)
			for index: int in body.options.size():
				var option := body.options[index]
				var label := option.label if not option.label.is_empty() else "Option %d" % (index + 1)
				_add_choice(grid, "%d · %s" % [index + 1, label], InteractionResponse.ChoiceBody.new(index), "Choice%d" % (index + 1))
			if request.kind == &"encounter_choice" and body.can_back_out:
				_add_choice(grid, "Back out", InteractionResponse.ChoiceBody.new(-1, true), "ChoiceBackOut")
		&"yes_no":
			var body := request.body as InteractionRequest.YesNoRequestBody
			if body == null: return
			var grid := _choice_grid(2, true)
			_add_choice(grid, body.yes_label, InteractionResponse.YesNoBody.new(true), "ChoiceYes")
			_add_choice(grid, body.no_label, InteractionResponse.YesNoBody.new(false), "ChoiceNo")
		&"acknowledge":
			var body := request.body as InteractionRequest.AcknowledgeBody
			if body == null: return
			var take_note_on_continue := body.journal_eligible and not body.journal_recorded and _autojournal_enabled
			_acknowledgement_body = InteractionResponse.AcknowledgeBody.new(take_note_on_continue)
			if body.prompt.strip_edges().is_empty():
				var grid := _choice_grid(1, true)
				var continue_button := Button.new()
				continue_button.name = "AcknowledgeContinue"
				continue_button.text = "Continue"
				continue_button.custom_minimum_size = Vector2(140.0, 38.0)
				continue_button.theme_type_variation = &"ClassicChoiceButton"
				continue_button.pressed.connect(submit_acknowledgement)
				grid.add_child(continue_button)
			if body.journal_eligible and not body.journal_recorded and not take_note_on_continue:
				_manual_journal_available = true


func submit_acknowledgement() -> bool:
	if _acknowledgement_body == null:
		return false
	var body := _acknowledgement_body
	_acknowledgement_body = null
	response_body_submitted.emit(body)
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if not _manual_journal_available or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_N:
		return
	_manual_journal_available = false
	_acknowledgement_body = null
	response_body_submitted.emit(InteractionResponse.AcknowledgeBody.new(true))
	get_viewport().set_input_as_handled()


func _choice_grid(columns: int, content_width: bool = false) -> GridContainer:
	var pane := PanelContainer.new()
	pane.name = "ChoicePane"
	pane.theme_type_variation = &"ClassicInset"
	pane.size_flags_horizontal = Control.SIZE_SHRINK_END if content_width else Control.SIZE_EXPAND_FILL
	add_child(pane)
	var grid := GridContainer.new()
	grid.name = "ChoiceGrid"
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	pane.add_child(grid)
	return grid


func _add_choice(parent: Container, label: String, body: InteractionResponse.Body, node_name: String) -> void:
	var button := add_response_to(parent, label, body)
	button.name = node_name
	button.custom_minimum_size = Vector2(140.0, 38.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.theme_type_variation = &"ClassicChoiceButton"
