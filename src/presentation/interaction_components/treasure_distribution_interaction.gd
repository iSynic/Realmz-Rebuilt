class_name TreasureDistributionInteraction
extends InteractionComponent


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.TreasureRequestBody
	if body == null:
		add_hint("The treasure request is malformed.")
	elif body.mode == &"fumbled-item-recovery":
		_build_fumble_recovery(body)
	elif body.mode == &"ordinary":
		_build_ordinary(body)
	elif body.mode == &"completion-confirmation":
		_build_completion_confirmation(body)
	else:
		add_hint("The treasure request is malformed.")


func _build_fumble_recovery(body: InteractionRequest.TreasureRequestBody) -> void:
	if body.item == null:
		add_hint("The recovery request is malformed.")
		return
	var instance_id := body.item.instance_id
	var charge_count := body.item.charges
	var charge_text := " • %d charge%s" % [charge_count, "" if charge_count == 1 else "s"] if charge_count > 0 else ""
	var remaining_text := " • %d items remain" % body.remaining if body.remaining > 1 else ""
	add_hint("%s%s%s" % [body.item.name, charge_text, remaining_text])
	_add_item_recipients(instance_id, body.characters)
	add_response("Leave behind", InteractionResponse.TreasureBody.new(&"discard", instance_id))


func _build_ordinary(body: InteractionRequest.TreasureRequestBody) -> void:
	if body.wealth != null:
		add_hint("Pool: %d gold • %d gems • %d jewelry" % [body.wealth.gold, body.wealth.gems, body.wealth.jewelry])
	if body.experience_share > 0:
		add_hint("Each eligible adventurer receives %d experience." % body.experience_share)
	if body.item != null:
		var instance_id := body.item.instance_id
		var display_name := body.item.name
		if body.item.magical and not body.item.identified:
			display_name += " • magic detected"
		add_hint("%s • %d item%s remain" % [display_name, body.remaining, "" if body.remaining == 1 else "s"])
		_add_item_recipients(instance_id, body.characters)
		add_response("Leave this item", InteractionResponse.TreasureBody.new(&"discard", instance_id))
	elif body.remaining == 0:
		add_hint("No items remain to distribute.")
	if body.detect != null and body.detect.visible:
		_add_caster_actions("Detect magic", "detect", body.detect)
	if body.identify != null and body.identify.visible:
		_add_caster_actions("Identify treasure", "identify", body.identify)
	var has_carried_wealth := false
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		if character.wealth != null:
			has_carried_wealth = has_carried_wealth or character.wealth.gold > 0 or character.wealth.gems > 0 or character.wealth.jewelry > 0
	add_response("Pool party wealth", InteractionResponse.TreasureBody.new(&"pool"), has_carried_wealth, "No adventurer carries wealth to pool.")
	var has_pool := body.wealth != null and (body.wealth.gold > 0 or body.wealth.gems > 0 or body.wealth.jewelry > 0)
	add_response("Share pooled wealth", InteractionResponse.TreasureBody.new(&"share"), has_pool and body.has_share_capacity, "The pool is empty or no adventurer can carry another unit.")
	_add_swap_controls(body.characters)
	add_response("Done", InteractionResponse.TreasureBody.new(&"done"))


func _build_completion_confirmation(body: InteractionRequest.TreasureRequestBody) -> void:
	add_hint(body.summary if not body.summary.is_empty() else "Unclaimed treasure will be left behind.")
	add_response("Return to treasure", InteractionResponse.TreasureBody.new(&"cancel-completion"))
	add_response("Leave it behind", InteractionResponse.TreasureBody.new(&"confirm-completion"))


func _add_item_recipients(instance_id: String, characters: Array[InteractionRequestValue.RewardCharacter]) -> void:
	for character: InteractionRequestValue.RewardCharacter in characters:
		add_response("Give to %s" % character.name, InteractionResponse.TreasureBody.new(&"assign", instance_id, character.id), character.enabled, character.reason)


func _add_caster_actions(label: String, action: String, method: InteractionRequestValue.RewardMethod) -> void:
	if not method.casters.is_empty():
		for caster: InteractionRequestValue.RewardCaster in method.casters:
			add_response("%s — %s" % [label, caster.name], InteractionResponse.TreasureBody.new(StringName(action), "", caster.id))
	else:
		add_response(label, InteractionResponse.TreasureBody.new(StringName(action)), false, method.reason if not method.reason.is_empty() else "Unavailable.")


func _add_swap_controls(characters: Array[InteractionRequestValue.RewardCharacter]) -> void:
	var rows: Array[InteractionRequestValue.RewardCharacter] = []
	for character: InteractionRequestValue.RewardCharacter in characters:
		if character.wealth != null and not character.id.is_empty(): rows.append(character)
	if rows.is_empty():
		return
	add_hint("Swap wealth in Classic increments: 5 gold, 1 gem, or 1 jewelry.")
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: InteractionRequestValue.RewardCharacter in rows:
		selector.add_item(row.name)
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


func _submit_swap(selector: OptionButton, rows: Array[InteractionRequestValue.RewardCharacter], direction: String, kind: String, amount: int) -> void:
	if selector.selected < 0 or selector.selected >= rows.size():
		return
	response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"transfer", "", rows[selector.selected].id, StringName(direction), StringName(kind), amount))


func _refresh_swap_controls(index: int, selector: OptionButton, rows: Array[InteractionRequestValue.RewardCharacter], summary: Label, buttons: Array[Button], specs: Array[Dictionary]) -> void:
	if index < 0 or index >= rows.size():
		return
	selector.select(index)
	var row := rows[index]
	var carried := row.wealth
	summary.text = "%s carries %d gold • %d gems • %d jewelry" % [row.name, carried.gold, carried.gems, carried.jewelry]
	for button_index: int in buttons.size():
		var spec: Dictionary = specs[button_index]
		var enabled := false
		var reason := ""
		if spec["direction"] == "to-character":
			match String(spec["kind"]):
				"gold": enabled = row.can_take_gold; reason = row.gold_reason
				"gems": enabled = row.can_take_gems; reason = row.gems_reason
				"jewelry": enabled = row.can_take_jewelry; reason = row.jewelry_reason
		else:
			var carried_amount := carried.gold if spec["kind"] == "gold" else carried.gems if spec["kind"] == "gems" else carried.jewelry
			enabled = carried_amount >= int(spec["amount"])
			reason = "This adventurer does not carry enough %s." % String(spec["kind"])
		buttons[button_index].disabled = not enabled
		buttons[button_index].tooltip_text = "" if enabled else reason
