class_name TreasureDistributionInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")

var _compact := false


func configure(compact: bool) -> void:
	_compact = compact


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.TreasureRequestBody
	if body == null:
		add_hint("The treasure request is malformed.")
		return
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0)
	match body.mode:
		&"fumbled-item-recovery":
			_build_workspace(body, true)
		&"ordinary":
			_build_workspace(body, false)
		&"completion-confirmation":
			_build_completion_confirmation(body)
		_:
			add_hint("The treasure request is malformed.")


func _build_workspace(body: InteractionRequest.TreasureRequestBody, recovering_fumble: bool) -> void:
	if recovering_fumble and body.item == null:
		add_hint("The recovery request is malformed.")
		return
	_add_workspace_header(body, recovering_fumble)
	var columns := HBoxContainer.new()
	columns.name = "TreasureWorkspaceColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	add_child(columns)
	var item_column := _add_column(columns, "TreasureItemColumn", "Dropped Item" if recovering_fumble else "Current Item", 280.0, 1.2 if recovering_fumble else 1.35)
	var recipient_column := _add_column(columns, "TreasureRecipientColumn", "Recover To" if recovering_fumble else "Assign To", 220.0, 1.0)
	_build_item_column(item_column, body, recovering_fumble)
	_build_recipient_column(recipient_column, body, recovering_fumble)
	if not recovering_fumble:
		var command_column := _add_column(columns, "TreasureCommandColumn", "Party Wealth", 180.0, 0.82)
		_build_command_column(command_column, body)
	_build_footer(body, recovering_fumble)


func _add_workspace_header(body: InteractionRequest.TreasureRequestBody, recovering_fumble: bool) -> void:
	var header := HBoxContainer.new()
	header.name = "TreasureWorkspaceHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)
	var title := Label.new()
	title.name = "TreasureWorkspaceTitle"
	title.theme_type_variation = &"ClassicHeading"
	title.text = "Recover Fumbled Item" if recovering_fumble else "Victory Spoils" if body.origin == &"battle" else "Treasure"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var summary := Label.new()
	summary.name = "TreasureWorkspaceSummary"
	summary.text = _summary_text(body)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	summary.add_theme_color_override("font_color", CYAN)
	header.add_child(summary)


func _add_column(parent: HBoxContainer, column_name: String, title_text: String, minimum_width: float, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = column_name
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 0.0 if _compact else minimum_width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "%sContent" % column_name
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var heading := Label.new()
	heading.name = "%sHeading" % column_name
	heading.theme_type_variation = &"ClassicHeading"
	heading.text = title_text
	column.add_child(heading)
	return column


func _build_item_column(column: VBoxContainer, body: InteractionRequest.TreasureRequestBody, recovering_fumble: bool) -> void:
	if body.item == null:
		_add_muted_label(column, "No items remain to distribute.", "TreasureEmptyItem")
	else:
		column.add_child(_loot_marker())
		var card := PanelContainer.new()
		card.name = "TreasureSelectedItem"
		card.theme_type_variation = &"ClassicInset"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(card)
		var facts := VBoxContainer.new()
		facts.name = "TreasureSelectedItemFacts"
		facts.add_theme_constant_override("separation", 2)
		card.add_child(facts)
		var item_name := Label.new()
		item_name.name = "TreasureSelectedItemName"
		item_name.theme_type_variation = &"ClassicHeading"
		item_name.text = body.item.name
		item_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		facts.add_child(item_name)
		_add_colored_label(facts, _item_state(body.item), CYAN, "TreasureSelectedItemState")
		if body.item.charges > 0:
			_add_muted_label(facts, "%d charge%s" % [body.item.charges, "" if body.item.charges == 1 else "s"], "TreasureSelectedItemCharges")
	var remaining := "No items remain." if body.item == null or body.remaining <= 0 else "This is the final item." if body.remaining == 1 else "%d items remain including this selection." % body.remaining
	_add_colored_label(column, remaining, GOLD, "TreasureRemainingItems")
	if not body.prompt.is_empty():
		_add_muted_label(column, body.prompt, "TreasurePrompt")
	if body.experience_share > 0 and not recovering_fumble:
		_add_colored_label(column, "Each eligible adventurer receives %d experience." % body.experience_share, GOLD, "TreasureExperienceShare")
	if body.item != null:
		_add_muted_label(column, "Exact item art is unavailable for this reward record.", "TreasureMediaUnavailable")


func _build_recipient_column(column: VBoxContainer, body: InteractionRequest.TreasureRequestBody, recovering_fumble: bool) -> void:
	_add_muted_label(column, "Choose an eligible adventurer to recover this exact item." if recovering_fumble else "Choose who receives the selected item.", "TreasureRecipientHint")
	var scroll := ScrollContainer.new()
	scroll.name = "TreasureRecipientScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "TreasureRecipientRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	scroll.add_child(rows)
	if body.characters.is_empty():
		_add_muted_label(rows, "No recipient is available.", "TreasureNoRecipients")
		return
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		var label := "%s%s" % ["Recover to " if recovering_fumble else "", _recipient_text(character)]
		var button := add_response_to(rows, label, InteractionResponse.TreasureBody.new(&"assign", body.item.instance_id if body.item != null else "", character.id), character.enabled and body.item != null, character.reason)
		button.name = "TreasureRecipient_%s" % character.id
		button.custom_minimum_size.y = 48.0
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT


func _build_command_column(column: VBoxContainer, body: InteractionRequest.TreasureRequestBody) -> void:
	_add_colored_label(column, _wealth_text(body.wealth), GOLD, "TreasurePooledWealth")
	var wealth_actions := HBoxContainer.new()
	wealth_actions.name = "TreasureWealthActions"
	wealth_actions.add_theme_constant_override("separation", 4)
	column.add_child(wealth_actions)
	var has_carried_wealth := body.characters.any(func(character: InteractionRequestValue.RewardCharacter) -> bool:
		return character.wealth != null and (character.wealth.gold > 0 or character.wealth.gems > 0 or character.wealth.jewelry > 0)
	)
	add_response_to(wealth_actions, "Pool", InteractionResponse.TreasureBody.new(&"pool"), has_carried_wealth, "No adventurer carries wealth to pool.")
	var has_pool := body.wealth != null and (body.wealth.gold > 0 or body.wealth.gems > 0 or body.wealth.jewelry > 0)
	add_response_to(wealth_actions, "Share", InteractionResponse.TreasureBody.new(&"share"), has_pool and body.has_share_capacity, "The pool is empty or no adventurer can carry another unit.")
	_add_swap_controls(column, body.characters)
	if (body.detect != null and body.detect.visible) or (body.identify != null and body.identify.visible):
		var lore_heading := Label.new()
		lore_heading.name = "TreasureLoreHeading"
		lore_heading.theme_type_variation = &"ClassicHeading"
		lore_heading.text = "Item Lore"
		column.add_child(lore_heading)
	if body.detect != null and body.detect.visible:
		_add_caster_control(column, "Detect Magic", &"detect", body.detect)
	if body.identify != null and body.identify.visible:
		_add_caster_control(column, "Identify", &"identify", body.identify)
	_add_expanding_spacer(column, "TreasureCommandSpacer")


func _build_footer(body: InteractionRequest.TreasureRequestBody, recovering_fumble: bool) -> void:
	var footer := HBoxContainer.new()
	footer.name = "TreasureFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 6)
	add_child(footer)
	var item_id := body.item.instance_id if body.item != null else ""
	if body.item != null:
		var leave := add_response_to(footer, "Leave Item", InteractionResponse.TreasureBody.new(&"discard", item_id))
		leave.name = "TreasureLeaveItem"
		leave.custom_minimum_size.x = 160.0
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	if not recovering_fumble:
		var done := add_response_to(footer, "Done", InteractionResponse.TreasureBody.new(&"done"))
		done.name = "TreasureDone"
		done.custom_minimum_size.x = 160.0


func _loot_marker() -> CenterContainer:
	var center := CenterContainer.new()
	center.name = "TreasureLootField"
	center.custom_minimum_size.y = 132.0 if not _compact else 104.0
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(130.0, 124.0) if not _compact else Vector2(100.0, 96.0)
	center.add_child(stage)
	var scale := 2.0 if not _compact else 1.5
	var glow := TextureRect.new()
	glow.name = "TreasureItemGlow"
	glow.texture = ClassicUiAssetCatalog.texture(&"loot.item.glow")
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.size = Vector2(48.0, 48.0) * scale
	glow.position = (stage.custom_minimum_size - glow.size) * 0.5
	stage.add_child(glow)
	var selection := TextureRect.new()
	selection.name = "TreasureSelectionCircle"
	selection.texture = ClassicUiAssetCatalog.texture(&"loot.selection")
	selection.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	selection.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selection.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selection.size = Vector2(50.0, 60.0) * scale
	selection.position = (stage.custom_minimum_size - selection.size) * 0.5
	stage.add_child(selection)
	return center


func _add_swap_controls(parent: VBoxContainer, characters: Array[InteractionRequestValue.RewardCharacter]) -> void:
	var rows: Array[InteractionRequestValue.RewardCharacter] = []
	for character: InteractionRequestValue.RewardCharacter in characters:
		if character.wealth != null and not character.id.is_empty():
			rows.append(character)
	if rows.is_empty():
		return
	var heading := Label.new()
	heading.name = "TreasureSwapHeading"
	heading.text = "Swap Wealth"
	heading.add_theme_color_override("font_color", CYAN)
	parent.add_child(heading)
	var selector := OptionButton.new()
	selector.name = "TreasureSwapCharacter"
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: InteractionRequestValue.RewardCharacter in rows:
		selector.add_item(row.name)
	parent.add_child(selector)
	var summary := Label.new()
	summary.name = "TreasureSwapSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", MUTED)
	parent.add_child(summary)
	var grid := GridContainer.new()
	grid.name = "TreasureSwapGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	var specs: Array[Dictionary] = [
		{"label": "+5 Gold", "direction": "to-character", "kind": "gold", "amount": 5},
		{"label": "-5 Gold", "direction": "to-pool", "kind": "gold", "amount": 5},
		{"label": "+1 Gem", "direction": "to-character", "kind": "gems", "amount": 1},
		{"label": "-1 Gem", "direction": "to-pool", "kind": "gems", "amount": 1},
		{"label": "+1 Jewelry", "direction": "to-character", "kind": "jewelry", "amount": 1},
		{"label": "-1 Jewelry", "direction": "to-pool", "kind": "jewelry", "amount": 1},
	]
	var buttons: Array[Button] = []
	for spec: Dictionary in specs:
		var button := Button.new()
		button.name = "TreasureSwap_%s_%s" % [spec["direction"], spec["kind"]]
		button.text = spec["label"]
		button.custom_minimum_size.y = 28.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_submit_swap.bind(selector, rows, String(spec["direction"]), String(spec["kind"]), int(spec["amount"])))
		grid.add_child(button)
		buttons.append(button)
	selector.item_selected.connect(_refresh_swap_controls.bind(selector, rows, summary, buttons, specs))
	_refresh_swap_controls(0, selector, rows, summary, buttons, specs)


func _add_caster_control(parent: VBoxContainer, label: String, action: StringName, method: InteractionRequestValue.RewardMethod) -> void:
	if method.casters.is_empty():
		add_response_to(parent, label, InteractionResponse.TreasureBody.new(action), false, method.reason if not method.reason.is_empty() else "Unavailable.")
		return
	var row := HBoxContainer.new()
	row.name = "Treasure%sRow" % label.replace(" ", "")
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var selector := OptionButton.new()
	selector.name = "Treasure%sCaster" % label.replace(" ", "")
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for caster: InteractionRequestValue.RewardCaster in method.casters:
		selector.add_item("%s • %d SP" % [caster.name, caster.cost])
	row.add_child(selector)
	var button := Button.new()
	button.name = "Treasure%sAction" % label.replace(" ", "")
	button.text = label
	button.pressed.connect(func() -> void:
		if selector.selected >= 0 and selector.selected < method.casters.size():
			response_body_submitted.emit(InteractionResponse.TreasureBody.new(action, "", method.casters[selector.selected].id))
	)
	row.add_child(button)


func _build_completion_confirmation(body: InteractionRequest.TreasureRequestBody) -> void:
	var panel := PanelContainer.new()
	panel.name = "TreasureCompletionConfirmation"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(panel)
	var column := VBoxContainer.new()
	column.name = "TreasureCompletionContent"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.name = "TreasureCompletionTitle"
	title.theme_type_variation = &"ClassicHeading"
	title.text = "Leave Treasure Behind?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_add_muted_label(column, body.summary if not body.summary.is_empty() else "Unclaimed treasure will be left behind.", "TreasureCompletionSummary")
	var actions := HBoxContainer.new()
	actions.name = "TreasureCompletionActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	add_response_to(actions, "Return to treasure", InteractionResponse.TreasureBody.new(&"cancel-completion"))
	add_response_to(actions, "Leave it behind", InteractionResponse.TreasureBody.new(&"confirm-completion"))


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
	summary.text = "%s: %d gold • %d gems • %d jewelry" % [row.name, carried.gold, carried.gems, carried.jewelry]
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


func _summary_text(body: InteractionRequest.TreasureRequestBody) -> String:
	var parts: Array[String] = []
	if body.has_remaining:
		parts.append("%d item%s" % [body.remaining, "" if body.remaining == 1 else "s"])
	if body.wealth != null:
		parts.append("%d gold" % body.wealth.gold)
	if body.experience_share > 0:
		parts.append("%d experience each" % body.experience_share)
	return " • ".join(parts)


func _recipient_text(character: InteractionRequestValue.RewardCharacter) -> String:
	if character.has_health:
		return "%s\nStamina %d/%d" % [character.name, character.current_health, character.maximum_health]
	if character.wealth != null:
		return "%s\n%d gold • %d gems • %d jewelry" % [character.name, character.wealth.gold, character.wealth.gems, character.wealth.jewelry]
	return character.name


func _wealth_text(wealth: InteractionRequestValue.Wealth) -> String:
	if wealth == null:
		return "Gold 0 • Gems 0 • Jewelry 0"
	return "Gold %d • Gems %d • Jewelry %d" % [wealth.gold, wealth.gems, wealth.jewelry]


func _item_state(item: InteractionRequestValue.RewardItem) -> String:
	if item.magical and not item.identified:
		return "Magic detected • unidentified"
	return "Identified" if item.identified else "Unidentified"


func _add_expanding_spacer(parent: Container, spacer_name: String) -> void:
	var spacer := Control.new()
	spacer.name = spacer_name
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


func _add_muted_label(parent: Container, text: String, label_name: String) -> Label:
	return _add_colored_label(parent, text, MUTED, label_name)


func _add_colored_label(parent: Container, text: String, color: Color, label_name: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
