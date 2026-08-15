class_name LevelUpInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.LevelUpRequestBody
	if body == null:
		add_hint("The level-up request is malformed.")
	elif body.mode == &"result":
		_build_result(body)
	elif body.mode == &"spell-selection":
		_build_spell_selection(body)
	else:
		add_hint("The level-up request is malformed.")


func _build_result(body: InteractionRequest.LevelUpRequestBody) -> void:
	if body.character_id.is_empty() or body.gains == null:
		add_hint("The level result is unavailable.")
		return
	add_hint("%s reached level %d." % [body.character_name, body.level])
	add_hint("Stamina +%d • Spell points +%d • To hit +%d • Magic resistance +%d" % [body.gains.stamina, body.gains.spell_points, body.gains.to_hit, body.gains.magic_resistance])
	add_response("Continue", InteractionResponse.LevelUpBody.new(&"continue", body.character_id))


func _build_spell_selection(body: InteractionRequest.LevelUpRequestBody) -> void:
	if body.character_id.is_empty():
		add_hint("The spell-selection request is unavailable.")
		return
	add_hint("Choose spells for %s. Available points: %d" % [body.character_name, body.point_total])
	var checklist := ItemList.new()
	checklist.select_mode = ItemList.SELECT_MULTI
	checklist.custom_minimum_size.y = 260.0
	checklist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for spell: InteractionRequestValue.SpellChoice in body.spells:
		checklist.add_item("%s • %d point%s" % [spell.name, spell.cost, "" if spell.cost == 1 else "s"])
		checklist.set_item_metadata(checklist.item_count - 1, spell.id)
		if spell.selected:
			checklist.select(checklist.item_count - 1, false)
	add_child(checklist)
	var confirm := Button.new()
	confirm.text = "Confirm spell selection"
	confirm.custom_minimum_size.y = 36.0
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.pressed.connect(func() -> void:
		var selected_ids: Array[String] = []
		for index: int in checklist.get_selected_items():
			selected_ids.append(String(checklist.get_item_metadata(index)))
		response_body_submitted.emit(InteractionResponse.LevelUpBody.new(&"confirm-spells", body.character_id, selected_ids))
	)
	add_child(confirm)
