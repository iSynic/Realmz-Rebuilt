class_name SpellsWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal route_requested(route_id: StringName)
signal refresh_requested
signal sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool)

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const SECTIONS: Array[StringName] = [&"known", &"fast", &"scrolls"]

var _view: GameView
var _media: ClassicMediaCatalog
var _text_scale: float = 1.0
var _selected_character_id: String = ""
var _selected_spell_id: String = ""
var _section_id: StringName = &"known"


func reset() -> void:
	_selected_character_id = ""
	_selected_spell_id = ""
	_section_id = &"known"


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null or view == null:
		return
	_view = view
	_media = media
	_text_scale = maxf(0.1, text_scale)
	if view.party_members.is_empty():
		_add_empty_state(parent, "No spellbooks", "The party has no characters.")
		return
	var character := _selected_character()
	if character == null:
		_add_empty_state(parent, "No spellbooks", "No party member can be selected.")
		return
	_add_character_selector(parent, character)
	_add_section_tabs(parent)
	match _section_id:
		&"fast":
			_add_fast_spells(parent, character)
		&"scrolls":
			_add_scrolls(parent, character)
		_:
			_add_known_spells(parent, character)


func _selected_character() -> CharacterView:
	for character: CharacterView in _view.party_members:
		if character.id == _selected_character_id:
			return character
	for character: CharacterView in _view.party_members:
		if not character.spells.is_empty():
			_selected_character_id = character.id
			return character
	var fallback: CharacterView = _view.party_members[0]
	_selected_character_id = fallback.id
	return fallback


func _add_character_selector(parent: VBoxContainer, character: CharacterView) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var picker := OptionButton.new()
	picker.name = "SpellCharacterSelector"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in _view.party_members.size():
		var candidate: CharacterView = _view.party_members[index]
		picker.add_item("%s  •  SP %d/%d" % [candidate.name, candidate.spell_points, candidate.maximum_spell_points])
		picker.set_item_metadata(index, candidate.id)
		if candidate.id == character.id:
			picker.select(index)
	picker.item_selected.connect(_select_character.bind(picker))
	row.add_child(picker)
	var context := _label("Camped" if _view.party_summary != null and _view.party_summary.camping else "Exploring", MUTED, 13)
	context.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(context)
	parent.add_child(panel)


func _add_section_tabs(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 5)
	for section_id: StringName in SECTIONS:
		var button := Button.new()
		button.text = {&"known": "Known Spells", &"fast": "Fast Spells", &"scrolls": "Scroll Case"}[section_id]
		button.toggle_mode = true
		button.button_pressed = section_id == _section_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34.0
		button.pressed.connect(_select_section.bind(section_id))
		row.add_child(button)
	parent.add_child(row)


func _add_known_spells(parent: VBoxContainer, character: CharacterView) -> void:
	if character.spells.is_empty():
		_add_empty_state(parent, "No known spells", "%s does not currently know a spell." % character.name)
		return
	var spell := _selected_spell(character)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	var list_panel := PanelContainer.new()
	list_panel.theme_type_variation = &"ClassicInset"
	list_panel.custom_minimum_size.x = 210.0
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list_panel.add_child(list)
	for candidate: SpellView in character.spells:
		var button := Button.new()
		button.text = "%s  •  %d SP" % [candidate.name, absi(candidate.cost)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = candidate.id == spell.id
		button.tooltip_text = candidate.description
		button.pressed.connect(_select_spell.bind(candidate.id))
		list.add_child(button)
	columns.add_child(list_panel)
	columns.add_child(_spell_detail(character, spell))
	parent.add_child(columns)


func _selected_spell(character: CharacterView) -> SpellView:
	for spell: SpellView in character.spells:
		if spell.id == _selected_spell_id:
			return spell
	var fallback: SpellView = character.spells[0]
	_selected_spell_id = fallback.id
	return fallback


func _spell_detail(character: CharacterView, spell: SpellView) -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	identity.add_child(_content_icon(spell.icon_resource_type, spell.icon_id))
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_label(title_box, spell.name, Color("e7d078"), 18)
	_add_label(title_box, "SP %d/%d  •  Base cost %d" % [character.spell_points, character.maximum_spell_points, absi(spell.cost)], MUTED, 13)
	identity.add_child(title_box)
	column.add_child(identity)
	_add_label(column, spell.description, Color("e0e2e5"), 14)
	_add_label(column, _spell_facts(spell), MUTED, 13)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 5)
	actions.add_theme_constant_override("v_separation", 5)
	_add_spell_actions(actions, character, spell)
	column.add_child(actions)
	return panel


func _spell_facts(spell: SpellView) -> String:
	var contexts: Array[String] = []
	if spell.castable_in_camp:
		contexts.append("camp")
	if spell.castable_in_combat:
		contexts.append("combat")
	return "Range %d–%d  •  Duration %d–%d  •  %s" % [spell.range_min, spell.range_max, spell.duration_min, spell.duration_max, " / ".join(contexts) if not contexts.is_empty() else "not castable here"]


func _add_spell_actions(parent: Container, character: CharacterView, spell: SpellView) -> void:
	if spell.power_levels.is_empty():
		_add_intent_action(parent, "Cast", spell.field_cast, PlayerIntent.cast_spell(spell.id, character.id))
	else:
		_add_power_action(parent, "Cast", spell.power_levels, spell.cost, spell.field_cast, func(picker: OptionButton) -> void:
			_cast_selected(character.id, spell.id, picker)
		)
	if spell.scroll_power_levels.is_empty():
		_add_intent_action(parent, "Make Scroll", spell.make_scroll, PlayerIntent.make_scroll(spell.id, character.id))
	else:
		_add_power_action(parent, "Make scroll", spell.scroll_power_levels, spell.cost * 2, spell.make_scroll, func(picker: OptionButton) -> void:
			_make_scroll_selected(character.id, spell.id, picker)
		)
	var back := Button.new()
	back.text = "Back to adventure"
	back.pressed.connect(func() -> void: route_requested.emit(&"exploration"))
	parent.add_child(back)


func _add_power_action(parent: Container, label: String, powers: Array[int], cost: int, availability: ActionAvailabilityView, callback: Callable) -> void:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", 4)
	var picker := OptionButton.new()
	picker.name = "%sPower" % label.replace(" ", "")
	for power: int in powers:
		picker.add_item("P%d • %d SP" % [power, absi(cost * power)])
		picker.set_item_metadata(picker.item_count - 1, power)
	picker.disabled = availability == null or not availability.enabled
	picker.tooltip_text = "Unavailable" if availability == null else availability.reason if picker.disabled else "%s power" % label
	group.add_child(picker)
	_add_button(group, label, availability, func() -> void:
		callback.call(picker)
	)
	parent.add_child(group)


func _cast_selected(character_id: String, spell_id: String, picker: OptionButton) -> void:
	intent_submitted.emit(PlayerIntent.cast_spell(spell_id, character_id, "", int(picker.get_selected_metadata())))


func _make_scroll_selected(character_id: String, spell_id: String, picker: OptionButton) -> void:
	intent_submitted.emit(PlayerIntent.make_scroll(spell_id, character_id, int(picker.get_selected_metadata())))


func _add_fast_spells(parent: VBoxContainer, character: CharacterView) -> void:
	_add_section_heading(parent, "%s's Fast Spells" % character.name, "Top-row 1–0")
	for binding: FastSpellBindingView in character.fast_spells:
		_add_fast_spell_row(parent, character, binding)
	if character.fast_spells.is_empty():
		_add_empty_state(parent, "No Fast Spell slots", "This character has no Fast Spell bindings.")


func _add_fast_spell_row(parent: Container, character: CharacterView, binding: FastSpellBindingView) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var label := _add_label(row, "Slot %s" % binding.shortcut_label, GOLD, 13)
	label.custom_minimum_size.x = 52.0
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("Undefined Spell")
	picker.set_item_metadata(0, {"spellId": "", "power": 0})
	for known_spell: SpellView in character.spells:
		var powers: Array[int] = []
		powers.assign([1] if known_spell.cost < 0 else [1, 2, 3, 4, 5, 6, 7])
		for power: int in powers:
			picker.add_item("%s • P%d" % [known_spell.name, power])
			picker.set_item_metadata(picker.item_count - 1, {"spellId": known_spell.id, "power": power})
			if known_spell.id == binding.spell_id and power == binding.power:
				picker.select(picker.item_count - 1)
	row.add_child(picker)
	var availability := _view.availability(&"set_fast_spell")
	_add_button(row, "Set", availability, _set_fast_spell.bind(character.id, binding.slot_index, picker))
	var clear_availability := availability if not binding.spell_id.is_empty() else ActionAvailabilityView.new(&"set_fast_spell", false, "This slot is already empty.")
	_add_button(row, "Clear", clear_availability, _clear_fast_spell.bind(character.id, binding.slot_index))
	parent.add_child(row)


func _add_scrolls(parent: VBoxContainer, character: CharacterView) -> void:
	_add_section_heading(parent, "%s's Scroll Case" % character.name, "Five fixed Classic slots")
	for scroll: SpellScrollView in character.scrolls:
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"ClassicInset"
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		panel.add_child(row)
		var text := "Slot %d  •  %s%s" % [scroll.slot_index + 1, scroll.spell_name, "" if scroll.power == 0 else "  •  Power %d" % scroll.power]
		var label := _add_label(row, text, MUTED if scroll.power == 0 else Color("e0e2e5"), 14)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_add_intent_action(row, "Use", scroll.use, PlayerIntent.use_scroll(character.id, scroll.slot_index))
		parent.add_child(panel)
	if character.scrolls.is_empty():
		_add_empty_state(parent, "No scroll case", "This character has no Classic scroll slots.")


func _select_character(index: int, picker: OptionButton) -> void:
	var value: Variant = picker.get_item_metadata(index)
	_selected_character_id = str(value)
	_selected_spell_id = ""
	refresh_requested.emit()


func _select_section(section_id: StringName) -> void:
	_section_id = section_id
	refresh_requested.emit()


func _select_spell(spell_id: String) -> void:
	_selected_spell_id = spell_id
	refresh_requested.emit()


func _set_fast_spell(character_id: String, slot_index: int, picker: OptionButton) -> void:
	var selected: Variant = picker.get_selected_metadata()
	if not selected is Dictionary:
		return
	sound_requested.emit(144, false, false)
	intent_submitted.emit(PlayerIntent.set_fast_spell(character_id, slot_index, String(selected.get("spellId", "")), int(selected.get("power", 0))))


func _clear_fast_spell(character_id: String, slot_index: int) -> void:
	sound_requested.emit(144, false, false)
	intent_submitted.emit(PlayerIntent.set_fast_spell(character_id, slot_index))


func _add_intent_action(parent: Container, label: String, availability: ActionAvailabilityView, intent: PlayerIntent) -> Button:
	return _add_button(parent, label, availability, func() -> void: intent_submitted.emit(intent))


func _add_button(parent: Container, label: String, availability: ActionAvailabilityView, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(74.0, 34.0)
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _content_icon(resource_type: String, resource_id: int) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(52.0, 52.0)
	var asset: MediaAsset = _media.asset_by_resource(resource_type, resource_id) if _media != null and resource_id != 0 else null
	if asset != null:
		var image := Image.new()
		var bytes := _media.read_bytes(asset)
		var error := ERR_UNAVAILABLE
		match asset.path.get_extension().to_lower():
			"png": error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg": error = image.load_jpg_from_buffer(bytes)
			"webp": error = image.load_webp_from_buffer(bytes)
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
	frame.add_child(fallback)
	return frame


func _add_section_heading(parent: Container, title: String, detail: String = "") -> void:
	var row := HBoxContainer.new()
	var heading := _label(title, GOLD, 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	if not detail.is_empty():
		var note := _label(detail, MUTED, 13)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(note)
	parent.add_child(row)


func _add_empty_state(parent: Container, title: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	panel.add_child(column)
	column.add_child(_label(title, GOLD, 16))
	var body := _label(detail, MUTED, 13)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)
	parent.add_child(panel)


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var result := _label(text, color, size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result


func _label(text: String, color: Color, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", int(round(float(size) * _text_scale)))
	return result
