class_name TextChoiceInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	match request.kind:
		&"encounter_choice", &"scenario_choice":
			var body := request.body as InteractionRequest.ChoiceRequestBody
			if body == null: return
			var grid := _choice_grid(2 if body.options.size() > 1 else 1)
			for index: int in body.options.size():
				var option := body.options[index]
				var label := option.label if not option.label.is_empty() else "Option %d" % (index + 1)
				_add_choice(grid, "%d · %s" % [index + 1, label], InteractionResponse.ChoiceBody.new(index), "Choice%d" % (index + 1))
			if request.kind == &"encounter_choice" and body.can_back_out:
				_add_choice(grid, "Back out", InteractionResponse.ChoiceBody.new(-1, true), "ChoiceBackOut")
		&"yes_no":
			var body := request.body as InteractionRequest.YesNoRequestBody
			if body == null: return
			var grid := _choice_grid(2)
			_add_choice(grid, body.yes_label, InteractionResponse.YesNoBody.new(true), "ChoiceYes")
			_add_choice(grid, body.no_label, InteractionResponse.YesNoBody.new(false), "ChoiceNo")
		&"acknowledge":
			var body := request.body as InteractionRequest.AcknowledgeBody
			if body == null: return
			var grid := _choice_grid(1)
			if body.journal_eligible and not body.journal_recorded:
				_add_choice(grid, "Take note", InteractionResponse.AcknowledgeBody.new(true), "ChoiceTakeNote")
			elif body.journal_recorded:
				add_hint("Already recorded in the journal.")
			_add_choice(grid, "Continue", InteractionResponse.AcknowledgeBody.new(), "ChoiceContinue")


func _choice_grid(columns: int) -> GridContainer:
	var pane := PanelContainer.new()
	pane.name = "ChoicePane"
	pane.theme_type_variation = &"ClassicInset"
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	button.custom_minimum_size.y = 42.0
	button.theme_type_variation = &"ClassicChoiceButton"
