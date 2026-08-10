class_name LevelUpInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var mode := String(request.payload.get("mode", ""))
	if mode == "result":
		_build_result(request.payload)
	elif mode == "spell-selection":
		_build_spell_selection(request.payload)
	else:
		add_hint("The level-up request is malformed.")


func _build_result(payload: Dictionary) -> void:
	var character_id := String(payload.get("characterId", ""))
	if character_id.is_empty() or not payload.get("gains") is Dictionary:
		add_hint("The level result is unavailable.")
		return
	var gains: Dictionary = payload["gains"]
	add_hint("%s reached level %d." % [String(payload.get("characterName", "Character")), int(payload.get("level", 0))])
	add_hint("Stamina +%d • Spell points +%d • To hit +%d • Magic resistance +%d" % [int(gains.get("stamina", 0)), int(gains.get("spellPoints", 0)), int(gains.get("toHit", 0)), int(gains.get("magicResistance", 0))])
	add_response("Continue", {"action": "continue", "characterId": character_id})


func _build_spell_selection(payload: Dictionary) -> void:
	var character_id := String(payload.get("characterId", ""))
	var spells: Variant = payload.get("spells", [])
	if character_id.is_empty() or not spells is Array:
		add_hint("The spell-selection request is unavailable.")
		return
	add_hint("Choose spells for %s. Available points: %d" % [String(payload.get("characterName", "Character")), int(payload.get("pointTotal", 0))])
	var checklist := ItemList.new()
	checklist.select_mode = ItemList.SELECT_MULTI
	checklist.custom_minimum_size.y = 260.0
	checklist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for value: Variant in spells:
		if not value is Dictionary:
			continue
		var spell: Dictionary = value
		checklist.add_item("%s • %d point%s" % [String(spell.get("name", "Spell")), int(spell.get("cost", 0)), "" if int(spell.get("cost", 0)) == 1 else "s"])
		checklist.set_item_metadata(checklist.item_count - 1, String(spell.get("id", "")))
		if bool(spell.get("selected", false)):
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
		payload_submitted.emit({"action": "confirm-spells", "characterId": character_id, "spellIds": selected_ids})
	)
	add_child(confirm)
