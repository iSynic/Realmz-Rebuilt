class_name InventoryWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal refresh_requested

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")

var _query: String = ""
var _selected_character_id: String = ""
var _selected_item_instance_id: String = ""
var _text_scale: float = 1.0


func reset() -> void:
	_query = ""
	_selected_character_id = ""
	_selected_item_instance_id = ""


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null:
		return
	_clear(parent)
	_text_scale = maxf(text_scale, 0.1)
	if view == null:
		return
	if view.party_members.is_empty():
		_add_empty_state(parent, "No party inventory", "The party has no characters.")
		return
	var selected_character: CharacterView = _selected_character(view)
	if selected_character == null:
		selected_character = view.party_members[0]
		_selected_character_id = selected_character.id
		_selected_item_instance_id = ""
	_add_section_heading(parent, "Whose items?", "%d party members" % view.party_members.size())
	var character_row := HFlowContainer.new()
	character_row.add_theme_constant_override("h_separation", 6)
	character_row.add_theme_constant_override("v_separation", 6)
	for character: CharacterView in view.party_members:
		var character_button := Button.new()
		character_button.text = "%s  %d/%d" % [character.name, character.carried_load, character.maximum_load]
		character_button.button_pressed = character.id == selected_character.id
		character_button.toggle_mode = true
		character_button.pressed.connect(_select_character.bind(character.id))
		character_row.add_child(character_button)
	parent.add_child(character_row)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	var search := LineEdit.new()
	search.placeholder_text = "Filter visible item names…"
	search.text = _query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_submitted.connect(_set_query)
	filter_row.add_child(search)
	var clear_filter := Button.new()
	clear_filter.text = "Clear"
	clear_filter.disabled = _query.is_empty()
	clear_filter.pressed.connect(_clear_query)
	filter_row.add_child(clear_filter)
	parent.add_child(filter_row)
	var visible_items: Array[ItemView] = []
	for item: ItemView in selected_character.items:
		if _query.is_empty() or item.name.findn(_query) >= 0:
			visible_items.append(item)
	var selected_item: ItemView = _selected_item(visible_items)
	if selected_item == null and not visible_items.is_empty():
		selected_item = visible_items[0]
		_selected_item_instance_id = selected_item.instance_id
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var item_list := VBoxContainer.new()
	item_list.custom_minimum_size.x = 250.0
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(item_list)
	_add_label(item_list, "%s's carried items" % selected_character.name, GOLD, 16)
	if visible_items.is_empty():
		_add_label(item_list, "No items match this filter." if not _query.is_empty() else "No carried items.", MUTED)
	for item: ItemView in visible_items:
		var item_button := Button.new()
		item_button.text = "%s%s  %s" % ["◆ " if item.equipped else "", item.name, "(%d)" % item.charges if item.charges > 0 else ""]
		item_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_button.toggle_mode = true
		item_button.button_pressed = selected_item != null and item.instance_id == selected_item.instance_id
		item_button.tooltip_text = "Equipped" if item.equipped else "Carried"
		item_button.pressed.connect(_select_item.bind(item.instance_id))
		item_list.add_child(item_button)
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 300.0
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	columns.add_child(detail)
	if selected_item != null:
		_render_item_detail(detail, selected_item, selected_character, media)
	parent.add_child(columns)


func _selected_character(view: GameView) -> CharacterView:
	for character: CharacterView in view.party_members:
		if character.id == _selected_character_id:
			return character
	return null


func _selected_item(items: Array[ItemView]) -> ItemView:
	for item: ItemView in items:
		if item.instance_id == _selected_item_instance_id:
			return item
	return null


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_selected_item_instance_id = ""
	refresh_requested.emit()


func _set_query(value: String) -> void:
	_query = value.strip_edges()
	_selected_item_instance_id = ""
	refresh_requested.emit()


func _clear_query() -> void:
	_query = ""
	_selected_item_instance_id = ""
	refresh_requested.emit()


func _select_item(instance_id: String) -> void:
	_selected_item_instance_id = instance_id
	refresh_requested.emit()


func _render_item_detail(parent: VBoxContainer, item: ItemView, character: CharacterView, media: ClassicMediaCatalog) -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	title_row.add_child(_content_icon(item.icon_resource_type, item.icon_id, media))
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(title_box, item.name, GOLD, 20)
	_add_label(title_box, "%s • Weight %d • Charges %d" % ["Equipped" if item.equipped else "Carried", item.weight, item.charges], MUTED, 13)
	title_row.add_child(title_box)
	parent.add_child(title_row)
	_add_label(parent, item.description, Color("e0e2e5"))
	_add_label(parent, "Value %s" % [str(item.value) if item.identified else "Unknown until identified"], MUTED, 13)
	if not item.facts.is_empty():
		_add_label(parent, "Classic record", GOLD, 15)
		var facts := GridContainer.new()
		facts.columns = 2
		facts.add_theme_constant_override("h_separation", 14)
		facts.add_theme_constant_override("v_separation", 3)
		for fact: ItemFactView in item.facts:
			_add_label(facts, fact.label, MUTED, 13)
			_add_label(facts, fact.value, Color("e0e2e5"), 13)
		parent.add_child(facts)
	for property: String in item.properties:
		_add_label(parent, "• %s" % property, Color("e0e2e5"), 13)
	for restriction: String in item.restrictions:
		_add_label(parent, restriction, Color("dca9a9"), 13)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 5)
	actions.add_theme_constant_override("v_separation", 5)
	if item.equipped:
		_add_item_intent_action(actions, &"inventory.action.equipped", "Unequip", item.actions.unequip, PlayerIntent.item_action(PlayerIntent.Kind.UNEQUIP_ITEM, item.instance_id, character.id))
	else:
		_add_item_intent_action(actions, &"inventory.action.equipped", "Equip", item.actions.equip, PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, item.instance_id, character.id))
	_add_item_intent_action(actions, &"inventory.action.use", "Use", item.actions.use, PlayerIntent.use_item(item.instance_id, character.id))
	_add_item_intent_action(actions, &"inventory.action.identify", "Cast Identify", item.actions.identify, PlayerIntent.identify_carried_items(item.actions.identify_spell_id, item.actions.identify_caster_id, character.id))
	_add_item_intent_action(actions, &"inventory.action.join", "Join", item.actions.join, PlayerIntent.item_action(PlayerIntent.Kind.JOIN_ITEM, item.instance_id, character.id))
	_add_item_intent_action(actions, &"inventory.action.split", "Split", item.actions.split, PlayerIntent.item_action(PlayerIntent.Kind.SPLIT_ITEM, item.instance_id, character.id))
	_add_item_intent_action(actions, &"inventory.action.drop", "Drop", item.actions.drop, PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, item.instance_id, character.id))
	parent.add_child(actions)
	var disabled_actions: Array[String] = []
	var action_labels: Array[String] = ["Equip", "Unequip", "Use", "Identify", "Join", "Split", "Drop", "Trade"]
	var action_views: Array[ActionAvailabilityView] = [item.actions.equip, item.actions.unequip, item.actions.use, item.actions.identify, item.actions.join, item.actions.split, item.actions.drop, item.actions.trade]
	for index: int in action_views.size():
		if action_views[index] != null and not action_views[index].enabled and not action_views[index].reason.is_empty():
			disabled_actions.append("%s — %s" % [action_labels[index], action_views[index].reason])
	if not disabled_actions.is_empty():
		_add_label(parent, "Unavailable actions", GOLD, 14)
		for reason: String in disabled_actions:
			_add_label(parent, reason, MUTED, 12)
	_add_label(parent, "Trade with", GOLD, 15)
	if item.actions.trade_targets.is_empty():
		_add_label(parent, "No other party member is available.", MUTED, 13)
	else:
		var trade_row := HFlowContainer.new()
		trade_row.add_theme_constant_override("h_separation", 5)
		for target: ItemTransferTargetView in item.actions.trade_targets:
			var trade_button := Button.new()
			trade_button.text = "Give to %s" % target.character_name
			trade_button.disabled = not target.enabled
			trade_button.tooltip_text = target.reason
			if target.enabled:
				trade_button.pressed.connect(func() -> void: intent_submitted.emit(PlayerIntent.trade_item(item.instance_id, character.id, target.character_id)))
			trade_row.add_child(trade_button)
		parent.add_child(trade_row)
	_add_label(parent, "Classic has no ordinary party stash. Scenario opcode 36 equipment escrow is automatic and does not appear here.", MUTED, 12)


func _content_icon(resource_type: String, resource_id: int, media: ClassicMediaCatalog) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(52.0, 52.0)
	var asset: MediaAsset = media.asset_by_resource(resource_type, resource_id) if media != null and resource_id != 0 else null
	if asset != null:
		var bytes := media.read_bytes(asset)
		var image := Image.new()
		var error := ERR_UNAVAILABLE
		match asset.path.get_extension().to_lower():
			"png":
				error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg":
				error = image.load_jpg_from_buffer(bytes)
			"webp":
				error = image.load_webp_from_buffer(bytes)
		if error == OK:
			var texture := TextureRect.new()
			texture.texture = ImageTexture.create_from_image(image)
			texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			texture.tooltip_text = asset.label
			frame.add_child(texture)
			return frame
	var fallback := Label.new()
	fallback.text = "◈\n%d" % resource_id if resource_id != 0 else "◈"
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", MUTED)
	fallback.tooltip_text = "Package media unavailable for %s %d." % [resource_type, resource_id] if resource_id != 0 else "No package media identity was supplied."
	frame.add_child(fallback)
	return frame


func _add_item_intent_action(parent: Container, asset_id: StringName, label: String, availability: ActionAvailabilityView, intent: PlayerIntent) -> BaseButton:
	var button: BaseButton
	if ClassicUiAssetCatalog.definition(asset_id).is_empty():
		var text_button := Button.new()
		text_button.text = label
		text_button.custom_minimum_size = Vector2(64.0, 56.0)
		button = text_button
	else:
		button = _bitmap_button(asset_id, label)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		if button is ClassicBitmapButton:
			(button as ClassicBitmapButton).command_requested.connect(func(_command_id: StringName) -> void: intent_submitted.emit(intent))
		else:
			button.pressed.connect(func() -> void: intent_submitted.emit(intent))
	parent.add_child(button)
	return button


func _bitmap_button(asset_id: StringName, label: String) -> ClassicBitmapButton:
	var button := ClassicBitmapButton.new()
	button.configure({
		"id": asset_id,
		"asset_id": asset_id,
		"tooltip": label,
		"accelerator": "",
	}, 1)
	return button


func _add_section_heading(parent: VBoxContainer, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	parent.add_child(row)


func _add_empty_state(parent: VBoxContainer, title: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	panel.add_child(column)
	_add_label(column, title, GOLD, 16)
	var body := _label(detail, MUTED, 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	_add_label(column, "Realmz Rebuilt shows only facts supplied by the detached session view.", MUTED, 12)
	parent.add_child(panel)


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: VBoxContainer) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
