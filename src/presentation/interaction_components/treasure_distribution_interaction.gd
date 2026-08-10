class_name TreasureDistributionInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var mode := String(request.payload.get("mode", ""))
	if mode == "fumbled-item-recovery":
		_build_fumble_recovery(request.payload)
	elif mode == "ordinary":
		_build_ordinary(request.payload)
	elif mode == "completion-confirmation":
		_build_completion_confirmation(request.payload)
	else:
		add_hint("The treasure request is malformed.")


func _build_fumble_recovery(payload: Dictionary) -> void:
	if not payload.get("item") is Dictionary:
		add_hint("The recovery request is malformed.")
		return
	var item: Dictionary = payload["item"]
	var instance_id := String(item.get("instanceId", ""))
	var charge_count := int(item.get("charges", 0))
	var charge_text := " • %d charge%s" % [charge_count, "" if charge_count == 1 else "s"] if charge_count > 0 else ""
	var remaining_text := " • %d items remain" % int(payload.get("remaining", 1)) if int(payload.get("remaining", 1)) > 1 else ""
	add_hint("%s%s%s" % [String(item.get("name", "Fumbled weapon")), charge_text, remaining_text])
	_add_item_recipients(instance_id, payload.get("characters", []))
	add_response("Leave behind", {"action": "discard", "instanceId": instance_id})


func _build_ordinary(payload: Dictionary) -> void:
	var wealth: Variant = payload.get("wealth", {})
	if wealth is Dictionary:
		add_hint("Pool: %d gold • %d gems • %d jewelry" % [int(wealth.get("gold", 0)), int(wealth.get("gems", 0)), int(wealth.get("jewelry", 0))])
	var share := int(payload.get("experienceShare", 0))
	if share > 0:
		add_hint("Each eligible adventurer receives %d experience." % share)
	var item: Variant = payload.get("item")
	if item is Dictionary:
		var item_data: Dictionary = item
		var instance_id := String(item_data.get("instanceId", ""))
		var display_name := String(item_data.get("name", "Unknown item"))
		if bool(item_data.get("magical", false)) and not bool(item_data.get("identified", false)):
			display_name += " • magic detected"
		add_hint("%s • %d item%s remain" % [display_name, int(payload.get("remaining", 1)), "" if int(payload.get("remaining", 1)) == 1 else "s"])
		_add_item_recipients(instance_id, payload.get("characters", []))
		add_response("Leave this item", {"action": "discard", "instanceId": instance_id})
	elif int(payload.get("remaining", 0)) == 0:
		add_hint("No items remain to distribute.")
	var detect: Variant = payload.get("detect", {})
	if detect is Dictionary and bool(detect.get("visible", false)):
		_add_caster_actions("Detect magic", "detect", detect)
	var identify: Variant = payload.get("identify", {})
	if identify is Dictionary and bool(identify.get("visible", false)):
		_add_caster_actions("Identify treasure", "identify", identify)
	var characters: Variant = payload.get("characters", [])
	var has_carried_wealth := false
	if characters is Array:
		for value: Variant in characters:
			if value is Dictionary and value.get("wealth") is Dictionary:
				var carried: Dictionary = value["wealth"]
				has_carried_wealth = has_carried_wealth or int(carried.get("gold", 0)) > 0 or int(carried.get("gems", 0)) > 0 or int(carried.get("jewelry", 0)) > 0
	add_response("Pool party wealth", {"action": "pool"}, has_carried_wealth, "No adventurer carries wealth to pool.")
	var has_pool := wealth is Dictionary and (int(wealth.get("gold", 0)) > 0 or int(wealth.get("gems", 0)) > 0 or int(wealth.get("jewelry", 0)) > 0)
	add_response("Share pooled wealth", {"action": "share"}, has_pool and bool(payload.get("hasShareCapacity", false)), "The pool is empty or no adventurer can carry another unit.")
	_add_swap_controls(characters)
	add_response("Done", {"action": "done"})


func _build_completion_confirmation(payload: Dictionary) -> void:
	add_hint(String(payload.get("summary", "Unclaimed treasure will be left behind.")))
	add_response("Return to treasure", {"action": "cancel-completion"})
	add_response("Leave it behind", {"action": "confirm-completion"})


func _add_item_recipients(instance_id: String, characters: Variant) -> void:
	if characters is Array:
		for value: Variant in characters:
			if not value is Dictionary:
				continue
			var character: Dictionary = value
			add_response(
				"Give to %s" % String(character.get("name", "Character")),
				{"action": "assign", "instanceId": instance_id, "characterId": String(character.get("id", ""))},
				bool(character.get("enabled", false)),
				String(character.get("reason", ""))
			)


func _add_caster_actions(label: String, action: String, data: Dictionary) -> void:
	var casters: Variant = data.get("casters", [])
	if casters is Array and not casters.is_empty():
		for value: Variant in casters:
			if value is Dictionary:
				add_response("%s — %s" % [label, String(value.get("name", "Character"))], {"action": action, "characterId": String(value.get("id", ""))})
	else:
		add_response(label, {"action": action}, false, String(data.get("reason", "Unavailable.")))


func _add_swap_controls(characters: Variant) -> void:
	if not characters is Array:
		return
	var rows: Array[Dictionary] = []
	for value: Variant in characters:
		if value is Dictionary and value.get("wealth") is Dictionary and not String(value.get("id", "")).is_empty():
			rows.append(value)
	if rows.is_empty():
		return
	add_hint("Swap wealth in Classic increments: 5 gold, 1 gem, or 1 jewelry.")
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: Dictionary in rows:
		selector.add_item(String(row.get("name", "Character")))
	add_child(selector)
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	var specs: Array[Dictionary] = [
		{"label": "Take 5 gold", "direction": "to-character", "kind": "gold", "amount": 5, "enabled": "canTakeGold", "reason": "goldReason"},
		{"label": "Return 5 gold", "direction": "to-pool", "kind": "gold", "amount": 5},
		{"label": "Take 1 gem", "direction": "to-character", "kind": "gems", "amount": 1, "enabled": "canTakeGems", "reason": "gemsReason"},
		{"label": "Return 1 gem", "direction": "to-pool", "kind": "gems", "amount": 1},
		{"label": "Take 1 jewelry", "direction": "to-character", "kind": "jewelry", "amount": 1, "enabled": "canTakeJewelry", "reason": "jewelryReason"},
		{"label": "Return 1 jewelry", "direction": "to-pool", "kind": "jewelry", "amount": 1},
	]
	var buttons: Array[Button] = []
	for spec: Dictionary in specs:
		var button := Button.new()
		button.text = spec["label"]
		button.custom_minimum_size.y = 34.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_submit_swap.bind(selector, rows, String(spec["direction"]), String(spec["kind"]), int(spec["amount"])))
		grid.add_child(button)
		buttons.append(button)
	selector.item_selected.connect(_refresh_swap_controls.bind(selector, rows, summary, buttons, specs))
	_refresh_swap_controls(0, selector, rows, summary, buttons, specs)


func _submit_swap(selector: OptionButton, rows: Array[Dictionary], direction: String, kind: String, amount: int) -> void:
	if selector.selected < 0 or selector.selected >= rows.size():
		return
	payload_submitted.emit({"action": "transfer", "direction": direction, "kind": kind, "amount": amount, "characterId": String(rows[selector.selected]["id"])})


func _refresh_swap_controls(index: int, selector: OptionButton, rows: Array[Dictionary], summary: Label, buttons: Array[Button], specs: Array[Dictionary]) -> void:
	if index < 0 or index >= rows.size():
		return
	selector.select(index)
	var row: Dictionary = rows[index]
	var carried: Dictionary = row["wealth"]
	summary.text = "%s carries %d gold • %d gems • %d jewelry" % [String(row.get("name", "Character")), int(carried.get("gold", 0)), int(carried.get("gems", 0)), int(carried.get("jewelry", 0))]
	for button_index: int in buttons.size():
		var spec: Dictionary = specs[button_index]
		var enabled := false
		var reason := ""
		if spec["direction"] == "to-character":
			enabled = bool(row.get(spec["enabled"], false))
			reason = String(row.get(spec["reason"], "This transfer is unavailable."))
		else:
			enabled = int(carried.get(spec["kind"], 0)) >= int(spec["amount"])
			reason = "This adventurer does not carry enough %s." % String(spec["kind"])
		buttons[button_index].disabled = not enabled
		buttons[button_index].tooltip_text = "" if enabled else reason
