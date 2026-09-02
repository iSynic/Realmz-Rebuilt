class_name TempleInteraction
extends InteractionComponent

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")

var _media: ClassicMediaCatalog
var _compact := false
var _body: InteractionRequest.TempleRequestBody
var _characters: Array[InteractionRequestValue.ServiceCharacter] = []
var _services: Array[InteractionRequestValue.TempleService] = []
var _selected_character_id: String
var _selected_service_id: String
var _character_picker: OptionButton
var _inspector: VBoxContainer
var _purchase_button: Button
var _character_group := ButtonGroup.new()
var _service_group := ButtonGroup.new()


func configure(media: ClassicMediaCatalog, compact: bool) -> void:
	_media = media
	_compact = compact


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.TempleRequestBody
	if _body == null:
		add_hint("The temple request is malformed.")
		return
	_characters = _body.characters.duplicate()
	_services = _body.services.duplicate()
	_selected_character_id = _body.selected_character_id
	if _selected_character_id.is_empty() and not _characters.is_empty():
		_selected_character_id = _characters[0].id
	if not _services.is_empty():
		_selected_service_id = _services[0].id
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0)
	add_theme_constant_override("separation", 6)
	_build_header()
	if _compact:
		_build_compact_character_picker()
	var columns := HBoxContainer.new()
	columns.name = "TempleWorkspaceColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 6)
	add_child(columns)
	if not _compact:
		_build_character_pane(columns)
	_build_service_pane(columns)
	_build_inspector_pane(columns)
	_build_footer()
	_refresh_inspector()


func _build_header() -> void:
	var row := HBoxContainer.new()
	row.name = "TempleHeader"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	var title := _label("Temple", GOLD)
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var facts := _label("Rate %d%%  •  Pool %d gold" % [_body.cost_percent, _body.pooled_wealth.gold], CYAN)
	facts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(facts)


func _build_compact_character_picker() -> void:
	_character_picker = character_option(_characters)
	_character_picker.name = "TempleCharacterPicker"
	for index: int in _character_picker.item_count:
		if String(_character_picker.get_item_metadata(index)) == _selected_character_id:
			_character_picker.select(index)
			break
	_character_picker.item_selected.connect(func(_index: int) -> void:
		_selected_character_id = String(_character_picker.get_selected_metadata())
		_refresh_inspector()
	)
	add_child(_character_picker)


func _build_character_pane(parent: HBoxContainer) -> void:
	var content := _pane(parent, "TempleCharacters", "Adventurers", 0.9)
	var scroll := _scroll("TempleCharacterScroll")
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "TempleCharacterRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	scroll.add_child(rows)
	if _characters.is_empty():
		rows.add_child(_label("No eligible adventurer was supplied.", MUTED))
		return
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		var button := Button.new()
		button.name = "TempleCharacter_%s" % character.id.replace(".", "_")
		button.text = "%s\nHP %d/%d  •  %d gold" % [character.name, character.current_health, character.maximum_health, character.available_gold]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 54.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = _character_group
		button.icon = _portrait(character.portrait_id)
		button.expand_icon = true
		button.pressed.connect(_select_character.bind(character.id))
		rows.add_child(button)
		button.set_pressed_no_signal(character.id == _selected_character_id)


func _build_service_pane(parent: HBoxContainer) -> void:
	var content := _pane(parent, "TempleServices", "Services", 1.05)
	var scroll := _scroll("TempleServiceScroll")
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "TempleServiceRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 3)
	scroll.add_child(rows)
	if _services.is_empty():
		rows.add_child(_label("No temple services were supplied.", MUTED))
		return
	for service: InteractionRequestValue.TempleService in _services:
		var button := Button.new()
		button.name = "TempleService_%s" % service.id.replace("-", "_")
		button.text = "%s\n%d gold" % [service.label, service.cost]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 48.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = _service_group
		button.pressed.connect(_select_service.bind(service.id))
		rows.add_child(button)
		button.set_pressed_no_signal(service.id == _selected_service_id)


func _build_inspector_pane(parent: HBoxContainer) -> void:
	var content := _pane(parent, "TempleInspector", "Selected Service", 1.15)
	_inspector = VBoxContainer.new()
	_inspector.name = "TempleInspectorFacts"
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.add_theme_constant_override("separation", 3)
	content.add_child(_inspector)
	_purchase_button = Button.new()
	_purchase_button.name = "TemplePurchase"
	_purchase_button.text = "Purchase"
	_purchase_button.custom_minimum_size.y = 38.0
	_purchase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purchase_button.pressed.connect(_submit_service)
	content.add_child(_purchase_button)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.name = "TempleFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 5)
	add_child(footer)
	_add_action(footer, "TemplePool", "Pool", &"pool")
	_add_action(footer, "TempleShare", "Share", &"share")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_add_action(footer, "TempleLeave", "Leave Temple", &"leave")


func _select_character(character_id: String) -> void:
	_selected_character_id = character_id
	_refresh_inspector()


func _select_service(service_id: String) -> void:
	_selected_service_id = service_id
	_refresh_inspector()


func _refresh_inspector() -> void:
	if _inspector == null:
		return
	for child: Node in _inspector.get_children():
		_inspector.remove_child(child)
		child.free()
	var character := _character_by_id(_selected_character_id)
	var service := _service_by_id(_selected_service_id)
	if character == null:
		_inspector.add_child(_label("No adventurer is selected.", MUTED))
	if service == null:
		_inspector.add_child(_label("No service is selected.", MUTED))
	_purchase_button.disabled = character == null or service == null or service.cost > character.available_gold
	_purchase_button.tooltip_text = "Select an adventurer and a service." if character == null or service == null else "%s has %d available gold; %s costs %d gold." % [character.name, character.available_gold, service.label, service.cost] if _purchase_button.disabled else ""
	if character == null or service == null:
		return
	var identity := HBoxContainer.new()
	identity.name = "TempleSelectedCharacter"
	var portrait := TextureRect.new()
	portrait.name = "TempleSelectedPortrait"
	portrait.texture = _portrait(character.portrait_id)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(64.0, 64.0)
	identity.add_child(portrait)
	var character_facts := VBoxContainer.new()
	character_facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_facts.add_child(_label(character.name, GOLD))
	character_facts.add_child(_label("HP %d/%d  •  Load %d/%d" % [character.current_health, character.maximum_health, character.load, character.maximum_load], CYAN))
	character_facts.add_child(_label("Personal %d  •  Pool %d  •  Available %d gold" % [character.personal_gold, _body.pooled_wealth.gold, character.available_gold], MUTED))
	identity.add_child(character_facts)
	_inspector.add_child(identity)
	_inspector.add_child(_label(service.label, GOLD))
	_inspector.add_child(_label(service.description, MUTED))
	_inspector.add_child(_label("Cost: %d gold" % service.cost, CYAN))
	if character.conditions.is_empty():
		_inspector.add_child(_label("No active conditions.", MUTED))
	else:
		var condition_names: Array[String] = []
		for index: int in mini(5, character.conditions.size()):
			var condition := character.conditions[index]
			condition_names.append("%s %d" % [condition.name, condition.value])
		_inspector.add_child(_label("Conditions: %s" % ", ".join(condition_names), MUTED))
	if _purchase_button.disabled:
		_inspector.add_child(_label(_purchase_button.tooltip_text, Color("d48a78")))


func _submit_service() -> void:
	var character := _character_by_id(_selected_character_id)
	var service := _service_by_id(_selected_service_id)
	if character == null or service == null or service.cost > character.available_gold:
		return
	response_body_submitted.emit(InteractionResponse.TempleBody.new(&"service", character.id, service.id))


func _character_by_id(character_id: String) -> InteractionRequestValue.ServiceCharacter:
	for character: InteractionRequestValue.ServiceCharacter in _characters:
		if character.id == character_id:
			return character
	return null


func _service_by_id(service_id: String) -> InteractionRequestValue.TempleService:
	for service: InteractionRequestValue.TempleService in _services:
		if service.id == service_id:
			return service
	return null


func _pane(parent: HBoxContainer, pane_name: String, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = pane_name
	panel.theme_type_variation = &"ClassicTextWell"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	var heading := _label(title, GOLD)
	heading.theme_type_variation = &"ClassicHeading"
	content.add_child(heading)
	return content


func _scroll(scroll_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = scroll_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	return label


func _portrait(asset_id: String) -> Texture2D:
	return _media.image_texture(_media.asset_by_id(asset_id)) if _media != null and not asset_id.is_empty() else null


func _add_action(parent: Container, name_value: String, text: String, action: StringName) -> void:
	var button := Button.new()
	button.name = name_value
	button.text = text
	button.custom_minimum_size.y = 36.0
	button.custom_minimum_size.x = 120.0
	button.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TempleBody.new(action, _selected_character_id)))
	parent.add_child(button)
