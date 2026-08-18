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
				add_response_to(grid, "%d · %s" % [index + 1, label], InteractionResponse.ChoiceBody.new(index))
			if request.kind == &"encounter_choice" and body.can_back_out:
				add_response_to(grid, "Back out", InteractionResponse.ChoiceBody.new(-1, true))
		&"yes_no":
			var body := request.body as InteractionRequest.YesNoRequestBody
			if body == null: return
			var grid := _choice_grid(2)
			add_response_to(grid, body.yes_label, InteractionResponse.YesNoBody.new(true))
			add_response_to(grid, body.no_label, InteractionResponse.YesNoBody.new(false))
		&"acknowledge":
			var body := request.body as InteractionRequest.AcknowledgeBody
			if body == null: return
			var grid := _choice_grid(1)
			if body.journal_eligible and not body.journal_recorded:
				add_response_to(grid, "Take note", InteractionResponse.AcknowledgeBody.new(true))
			elif body.journal_recorded:
				add_hint("Already recorded in the journal.")
			add_response_to(grid, "Continue", InteractionResponse.AcknowledgeBody.new())


func _choice_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "ChoiceGrid"
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	return grid
