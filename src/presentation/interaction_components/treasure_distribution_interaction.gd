class_name TreasureDistributionInteraction
extends InteractionComponent

signal recipient_selected(character_id: String)

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")
const INK := Color("111315")
const ITEM_DETAIL_POPOVER_SCRIPT := preload("res://src/presentation/classic_item_detail_popover.gd")

var _compact := false
var _media: ClassicMediaCatalog
var _game_view: GameView
var _loot_slot_order: Array[String] = []
var _selected_recipient_id: String
var _selected_item: InteractionRequestValue.RewardItem
var _item_buttons: Dictionary = {}
var _recipient_buttons: Dictionary = {}
var _selection_rings: Dictionary = {}
var _selected_item_name: Label
var _selected_item_state: Label
var _selected_item_description: Label
var _selected_item_facts: GridContainer
var _transferring := false
var _transfer_item: InteractionRequestValue.RewardItem
var _transfer_origin := Vector2.ZERO
var _detail_popover: CanvasLayer


func configure(media: ClassicMediaCatalog, game_view: GameView, compact: bool, selected_recipient_id: String = "", loot_slot_order: Array[String] = []) -> void:
	_media = media
	_game_view = game_view
	_compact = compact
	_selected_recipient_id = selected_recipient_id
	_loot_slot_order.assign(loot_slot_order)


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.TreasureRequestBody
	if body == null:
		add_hint("The treasure request is malformed.")
		return
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0 if _compact else 0.0)
	_detail_popover = ITEM_DETAIL_POPOVER_SCRIPT.new()
	add_child(_detail_popover)
	_detail_popover.configure(_media, get_theme())
	match body.mode:
		&"fumbled-item-recovery":
			_build_workspace(body, true)
		&"ordinary":
			_build_classic_treasure_workspace(body)
		&"completion-confirmation":
			_build_completion_confirmation(body)
		_:
			add_hint("The treasure request is malformed.")


func preferred_initial_focus() -> Control:
	var recipient := _recipient_buttons.get(_selected_recipient_id) as Control
	return recipient if recipient != null and recipient.visible and not (recipient is BaseButton and (recipient as BaseButton).disabled) else null


func _build_classic_treasure_workspace(body: InteractionRequest.TreasureRequestBody) -> void:
	_select_initial_recipient(body)
	_add_workspace_header(body, false)
	var workspace := HBoxContainer.new()
	workspace.name = "ClassicTreasureWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 6)
	add_child(workspace)
	_build_loot_side(workspace, body)
	_build_party_side(workspace, body)
	_build_item_inspector(body)
	_refresh_item_availability()


func _build_loot_side(parent: HBoxContainer, body: InteractionRequest.TreasureRequestBody) -> void:
	var column := VBoxContainer.new()
	column.name = "TreasureLootColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 2.3
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var field := PanelContainer.new()
	field.name = "TreasureLootField"
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.add_theme_stylebox_override("panel", _loot_field_style())
	column.add_child(field)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	field.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.name = "TreasureItemScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "TreasureItemGrid"
	grid.columns = 6 if _compact else 16
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	scroll.add_child(grid)
	if not _compact:
		scroll.resized.connect(_update_loot_columns.bind(scroll, grid))
		call_deferred("_update_loot_columns", scroll, grid)
	var items_by_id: Dictionary = {}
	for item: InteractionRequestValue.RewardItem in body.items:
		items_by_id[item.instance_id] = item
		if not _loot_slot_order.has(item.instance_id):
			_loot_slot_order.append(item.instance_id)
	if _loot_slot_order.is_empty():
		var empty := Label.new()
		empty.name = "TreasureEmptyField"
		empty.text = "No items remain."
		empty.add_theme_color_override("font_color", INK)
		grid.add_child(empty)
	else:
		_selected_item = body.items[0] if not body.items.is_empty() else null
		for slot_id: String in _loot_slot_order:
			var item := items_by_id.get(slot_id) as InteractionRequestValue.RewardItem
			if item != null:
				_add_loot_item(grid, item)
			else:
				_add_vacant_loot_slot(grid, slot_id)


func _build_item_inspector(body: InteractionRequest.TreasureRequestBody) -> void:
	var inspector: BoxContainer
	if _compact:
		inspector = VBoxContainer.new()
	else:
		inspector = HBoxContainer.new()
	inspector.name = "TreasureItemRecord"
	inspector.custom_minimum_size.y = 390.0 if _compact else 142.0
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 6)
	add_child(inspector)
	var identity_panel := PanelContainer.new()
	identity_panel.name = "TreasureItemIdentity"
	identity_panel.theme_type_variation = &"ClassicInset"
	identity_panel.custom_minimum_size.x = 0.0 if _compact else 360.0
	identity_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_panel.size_flags_stretch_ratio = 1.05
	inspector.add_child(identity_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	identity_panel.add_child(row)
	var record_icon := TextureRect.new()
	record_icon.name = "TreasureRecordIcon"
	record_icon.custom_minimum_size = Vector2(76.0, 76.0)
	record_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	record_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	record_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(record_icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 3)
	row.add_child(identity)
	_selected_item_name = _add_colored_label(identity, "", GOLD, "TreasureSelectedItemName")
	_selected_item_name.theme_type_variation = &"ClassicHeading"
	_selected_item_state = _add_colored_label(identity, "", CYAN, "TreasureSelectedItemState")
	_selected_item_description = _add_muted_label(identity, "", "TreasureSelectedItemDescription")
	_selected_item_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selected_item_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var property_panel := PanelContainer.new()
	property_panel.name = "TreasureItemProperties"
	property_panel.theme_type_variation = &"ClassicInset"
	property_panel.custom_minimum_size.x = 0.0 if _compact else 360.0
	property_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	property_panel.size_flags_stretch_ratio = 1.15
	inspector.add_child(property_panel)
	var properties := VBoxContainer.new()
	properties.add_theme_constant_override("separation", 4)
	property_panel.add_child(properties)
	var property_heading := _add_colored_label(properties, "Item Properties", GOLD, "TreasurePropertyHeading")
	property_heading.theme_type_variation = &"ClassicHeading"
	_selected_item_facts = GridContainer.new()
	_selected_item_facts.name = "TreasureSelectedItemFacts"
	_selected_item_facts.columns = 2 if _compact else 4
	_selected_item_facts.add_theme_constant_override("h_separation", 12)
	_selected_item_facts.add_theme_constant_override("v_separation", 3)
	properties.add_child(_selected_item_facts)
	var command_panel := PanelContainer.new()
	command_panel.name = "TreasureCommandPanel"
	command_panel.theme_type_variation = &"ClassicInset"
	command_panel.custom_minimum_size.x = 0.0 if _compact else 300.0
	command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_panel.size_flags_stretch_ratio = 0.8
	inspector.add_child(command_panel)
	var commands := VBoxContainer.new()
	commands.name = "TreasureCommands"
	commands.add_theme_constant_override("separation", 2)
	command_panel.add_child(commands)
	_build_compact_commands(commands, body)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	commands.add_child(spacer)
	var done := add_response_to(commands, "Done", InteractionResponse.TreasureBody.new(&"done"))
	done.name = "TreasureDone"
	_refresh_item_record(record_icon)


func _update_loot_columns(scroll: ScrollContainer, grid: GridContainer) -> void:
	if scroll == null or grid == null or _compact:
		return
	var available_width := maxf(50.0, scroll.size.x - 12.0)
	grid.columns = maxi(1, floori(available_width / 50.0))


func _add_loot_item(parent: GridContainer, item: InteractionRequestValue.RewardItem) -> void:
	var cell := Button.new()
	cell.name = "TreasureItem_%s" % _node_fragment(item.instance_id)
	cell.flat = true
	cell.focus_mode = Control.FOCUS_ALL
	cell.custom_minimum_size = Vector2(50.0, 60.0)
	cell.tooltip_text = item.name
	cell.set_meta("reward_item", item)
	parent.add_child(cell)
	if item.magical:
		var magic_glow := TextureRect.new()
		magic_glow.name = "TreasureMagicGlow_%s" % _node_fragment(item.instance_id)
		magic_glow.texture = ClassicUiAssetCatalog.texture(&"loot.item.glow")
		magic_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		magic_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		magic_glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		magic_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		magic_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(magic_glow)
	var icon_center := CenterContainer.new()
	icon_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon_center)
	var item_icon := TextureRect.new()
	item_icon.name = "TreasureLootIcon_%s" % _node_fragment(item.instance_id)
	item_icon.texture = _item_texture(item)
	item_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.custom_minimum_size = Vector2(32.0, 32.0)
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(item_icon)
	var ring := TextureRect.new()
	ring.name = "TreasureHoverCircle_%s" % _node_fragment(item.instance_id)
	ring.texture = ClassicUiAssetCatalog.texture(&"loot.selection")
	ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	cell.add_child(ring)
	_item_buttons[item.instance_id] = cell
	_selection_rings[item.instance_id] = ring
	cell.mouse_entered.connect(_focus_loot_item.bind(item, cell))
	cell.focus_entered.connect(_focus_loot_item.bind(item, cell))
	cell.mouse_exited.connect(_hide_loot_ring.bind(item.instance_id))
	cell.focus_exited.connect(_hide_loot_ring.bind(item.instance_id))
	cell.pressed.connect(_begin_item_transfer.bind(item, cell))
	_detail_popover.bind_hover(cell, _item_detail(item))


func _add_vacant_loot_slot(parent: GridContainer, instance_id: String) -> void:
	var slot := Control.new()
	slot.name = "TreasureVacantSlot_%s" % _node_fragment(instance_id)
	slot.custom_minimum_size = Vector2(50.0, 60.0)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)


func _build_party_side(parent: HBoxContainer, body: InteractionRequest.TreasureRequestBody) -> void:
	var panel := PanelContainer.new()
	panel.name = "TreasurePartyPanel"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 330.0 if not _compact else 250.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.95
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "TreasurePartyContent"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	var heading := _add_colored_label(column, "Choose Recipient", GOLD, "TreasureRecipientHeading")
	heading.theme_type_variation = &"ClassicHeading"
	var rows := VBoxContainer.new()
	rows.name = "TreasureRecipientRows"
	rows.add_theme_constant_override("separation", 2)
	column.add_child(rows)
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		_add_recipient_row(rows, character)
	if not body.prompt.is_empty():
		var message_panel := PanelContainer.new()
		message_panel.name = "TreasureMessagePanel"
		message_panel.theme_type_variation = &"ClassicInset"
		message_panel.custom_minimum_size.y = 42.0
		column.add_child(message_panel)
		var message_scroll := ScrollContainer.new()
		message_scroll.name = "TreasureMessageScroll"
		message_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		message_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		message_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		message_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		message_panel.add_child(message_scroll)
		var message := _add_muted_label(message_scroll, body.prompt, "TreasureNarrative")
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _add_recipient_row(parent: VBoxContainer, character: InteractionRequestValue.RewardCharacter) -> void:
	var button := Button.new()
	button.name = "TreasureRecipient_%s" % character.id
	button.toggle_mode = true
	button.button_pressed = character.id == _selected_recipient_id
	button.custom_minimum_size.y = 46.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = _recipient_text(character)
	button.icon = _portrait(character.id)
	button.add_theme_constant_override("icon_max_width", 38)
	button.expand_icon = true
	button.disabled = not character.enabled
	button.tooltip_text = character.reason
	button.pressed.connect(_select_recipient.bind(character.id))
	parent.add_child(button)
	_recipient_buttons[character.id] = button


func _build_compact_commands(parent: VBoxContainer, body: InteractionRequest.TreasureRequestBody) -> void:
	_add_colored_label(parent, _wealth_text(body.wealth), GOLD, "TreasurePooledWealth")
	var actions := HBoxContainer.new()
	actions.name = "TreasureWealthActions"
	actions.add_theme_constant_override("separation", 4)
	parent.add_child(actions)
	var has_carried_wealth := body.characters.any(func(character: InteractionRequestValue.RewardCharacter) -> bool:
		return character.wealth != null and (character.wealth.gold > 0 or character.wealth.gems > 0 or character.wealth.jewelry > 0)
	)
	add_response_to(actions, "Pool", InteractionResponse.TreasureBody.new(&"pool"), has_carried_wealth, "No adventurer carries wealth to pool.")
	var has_pool := body.wealth != null and (body.wealth.gold > 0 or body.wealth.gems > 0 or body.wealth.jewelry > 0)
	add_response_to(actions, "Share", InteractionResponse.TreasureBody.new(&"share"), has_pool and body.has_share_capacity, "The pool is empty or no adventurer can carry another unit.")
	if body.detect != null and body.detect.visible:
		_add_caster_control(parent, "Detect Magic", &"detect", body.detect)
	if body.identify != null and body.identify.visible:
		_add_caster_control(parent, "Identify", &"identify", body.identify)


func _select_initial_recipient(body: InteractionRequest.TreasureRequestBody) -> void:
	if body.characters.any(func(character: InteractionRequestValue.RewardCharacter) -> bool: return character.id == _selected_recipient_id and character.enabled):
		return
	_selected_recipient_id = ""
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		if character.enabled:
			_selected_recipient_id = character.id
			break


func _select_recipient(character_id: String) -> void:
	if _transferring or not _recipient_buttons.has(character_id):
		return
	_selected_recipient_id = character_id
	recipient_selected.emit(character_id)
	for id: Variant in _recipient_buttons:
		(_recipient_buttons[id] as Button).set_pressed_no_signal(String(id) == character_id)
	_refresh_item_availability()


func _focus_loot_item(item: InteractionRequestValue.RewardItem, _button: Button) -> void:
	_selected_item = item
	var ring := _selection_rings.get(item.instance_id) as TextureRect
	if ring != null:
		ring.visible = true
	var record_icon := find_child("TreasureRecordIcon", true, false) as TextureRect
	_refresh_item_record(record_icon)
	_refresh_item_availability()


func _hide_loot_ring(instance_id: String) -> void:
	var ring := _selection_rings.get(instance_id) as TextureRect
	var button := _item_buttons.get(instance_id) as Button
	if ring != null and (button == null or not button.has_focus()):
		ring.visible = false


func _refresh_item_record(icon: TextureRect) -> void:
	if _selected_item_name == null or _selected_item_state == null or _selected_item_description == null or _selected_item_facts == null:
		return
	for child: Node in _selected_item_facts.get_children():
		child.queue_free()
	if _selected_item == null:
		_selected_item_name.theme_type_variation = &"ClassicHeading"
		_selected_item_name.add_theme_color_override("font_color", GOLD)
		_selected_item_name.text = "No items remain"
		_selected_item_state.text = ""
		_selected_item_description.text = ""
		if icon != null: icon.texture = null
		return
	_selected_item_name.theme_type_variation = &"ClassicHeading" if _selected_item.identified else &"ClassicUnidentifiedItem"
	if _selected_item.identified:
		_selected_item_name.add_theme_color_override("font_color", GOLD)
	else:
		_selected_item_name.remove_theme_color_override("font_color")
	_selected_item_name.text = _selected_item.name
	_selected_item_state.text = _item_state(_selected_item)
	_selected_item_description.text = _selected_item.description
	for fact: InteractionRequestValue.RewardFact in _selected_item.facts:
		var label := _add_muted_label(_selected_item_facts, fact.label, "TreasureFact_%s" % fact.label.to_snake_case())
		label.add_theme_color_override("font_color", GOLD)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 96.0
		var value := _add_muted_label(_selected_item_facts, fact.value, "TreasureFactValue_%s" % fact.label.to_snake_case())
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if icon != null: icon.texture = _item_texture(_selected_item)


func _refresh_item_availability() -> void:
	for item_id: Variant in _item_buttons:
		var button := _item_buttons[item_id] as Button
		var item := _item_by_id(String(item_id))
		var assignment := _assignment_for(item, _selected_recipient_id)
		button.disabled = _transferring or assignment == null or not assignment.enabled
		button.tooltip_text = item.name if assignment != null and assignment.enabled else "%s — %s" % [item.name, assignment.reason if assignment != null else "Choose an eligible recipient."]


func _begin_item_transfer(item: InteractionRequestValue.RewardItem, source: Button) -> void:
	var assignment := _assignment_for(item, _selected_recipient_id)
	var target := _recipient_buttons.get(_selected_recipient_id) as Button
	if _transferring or assignment == null or not assignment.enabled or target == null:
		return
	_transferring = true
	_transfer_item = item
	_transfer_origin = source.get_global_rect().get_center()
	_refresh_item_availability()
	response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"assign", item.instance_id, _selected_recipient_id))


func take_committed_transfer_path() -> Dictionary:
	if not _transferring or _transfer_item == null:
		return {}
	var path := {
		"from": _transfer_origin,
		"texture": _item_texture(_transfer_item),
		"instanceId": _transfer_item.instance_id,
	}
	_transferring = false
	_transfer_item = null
	_transfer_origin = Vector2.ZERO
	return path


func _assignment_for(item: InteractionRequestValue.RewardItem, character_id: String) -> InteractionRequestValue.RewardAssignment:
	if item == null:
		return null
	for assignment: InteractionRequestValue.RewardAssignment in item.assignments:
		if assignment.character_id == character_id:
			return assignment
	return null


func _item_by_id(instance_id: String) -> InteractionRequestValue.RewardItem:
	if _selected_item != null and _selected_item.instance_id == instance_id:
		return _selected_item
	for child_item_id: Variant in _item_buttons:
		if String(child_item_id) == instance_id:
			var button := _item_buttons[child_item_id] as Button
			var item: Variant = button.get_meta("reward_item") if button.has_meta("reward_item") else null
			return item if item is InteractionRequestValue.RewardItem else null
	return null


func _item_texture(item: InteractionRequestValue.RewardItem) -> Texture2D:
	if _media == null or item == null or item.icon_id <= 0:
		return null
	return _media.image_texture(_media.asset_by_resource(item.icon_resource_type, item.icon_id))


func _portrait(character_id: String) -> Texture2D:
	if _game_view == null or _media == null:
		return null
	for character: CharacterView in _game_view.party_members:
		if character.id == character_id and not character.portrait_id.is_empty():
			return _media.image_texture(_media.asset_by_id(character.portrait_id))
	return null


static func _loot_field_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f7f6f0")
	style.border_color = Color("71777b")
	style.set_border_width_all(2)
	return style


static func _node_fragment(value: String) -> String:
	return value.replace(".", "_").replace(":", "_").replace("/", "_").replace("@", "_").replace('"', "_")


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
		column.add_child(_loot_marker(body.item))
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


func _loot_marker(item: InteractionRequestValue.RewardItem) -> CenterContainer:
	var center := CenterContainer.new()
	center.name = "TreasureLootField"
	center.custom_minimum_size.y = 132.0 if not _compact else 104.0
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(130.0, 124.0) if not _compact else Vector2(100.0, 96.0)
	center.add_child(stage)
	var marker_scale := 2.0 if not _compact else 1.5
	var glow := TextureRect.new()
	glow.name = "TreasureItemGlow"
	glow.texture = ClassicUiAssetCatalog.texture(&"loot.item.glow")
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.size = Vector2(48.0, 48.0) * marker_scale
	glow.position = (stage.custom_minimum_size - glow.size) * 0.5
	stage.add_child(glow)
	var asset: MediaAsset = _media.asset_by_resource(item.icon_resource_type, item.icon_id) if _media != null and item != null and item.icon_id != 0 else null
	var item_texture: Texture2D = _media.image_texture(asset) if _media != null and asset != null else null
	if item_texture != null:
		var item_icon := TextureRect.new()
		item_icon.name = "TreasureItemIcon"
		item_icon.texture = item_texture
		item_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_icon.size = Vector2(54.0, 54.0) * marker_scale
		item_icon.position = (stage.custom_minimum_size - item_icon.size) * 0.5
		item_icon.tooltip_text = item.name
		stage.add_child(item_icon)
	else:
		var unavailable := Label.new()
		unavailable.name = "TreasureItemIconUnavailable"
		unavailable.text = "◇"
		unavailable.tooltip_text = "Item image unavailable"
		unavailable.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unavailable.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		unavailable.size = Vector2(54.0, 54.0) * marker_scale
		unavailable.position = (stage.custom_minimum_size - unavailable.size) * 0.5
		unavailable.add_theme_color_override("font_color", MUTED)
		stage.add_child(unavailable)
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
	selector.theme_type_variation = &"ClassicTheldrowOptionButton"
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for caster: InteractionRequestValue.RewardCaster in method.casters:
		selector.add_item("%s • SP %d • Cost %d" % [caster.name, caster.spell_points, caster.cost])
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
		return "%s\nItems %d • Move %d • Load %d/%d" % [character.name, character.item_count, character.maximum_movement, character.carried_load, character.maximum_load]
	return character.name


func _wealth_text(wealth: InteractionRequestValue.Wealth) -> String:
	if wealth == null:
		return "Gold 0 • Gems 0 • Jewelry 0"
	return "Gold %d • Gems %d • Jewelry %d" % [wealth.gold, wealth.gems, wealth.jewelry]


func _item_state(item: InteractionRequestValue.RewardItem) -> String:
	if item.magical:
		return "Identified • magic detected" if item.identified else "Magic detected • unidentified"
	return "Identified" if item.identified else "Unidentified"


func _item_detail(item: InteractionRequestValue.RewardItem) -> Dictionary:
	var facts: Array[Dictionary] = []
	for fact: InteractionRequestValue.RewardFact in item.facts:
		facts.append({"label": fact.label, "value": fact.value})
	if item.charges != 0:
		facts.append({"label": "Charges", "value": "Unlimited" if item.charges < 0 else str(item.charges)})
	return {"title": item.name, "subtitle": _item_state(item), "description": item.description, "facts": facts, "iconResourceType": item.icon_resource_type, "iconId": item.icon_id}


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
