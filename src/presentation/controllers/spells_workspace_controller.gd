class_name SpellsWorkspaceController
extends RefCounted

signal intent_submitted(intent: PlayerIntent)
signal route_requested(route_id: StringName)
signal sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool)

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")

var _view: GameView
var _media: ClassicMediaCatalog
var _text_scale: float = 1.0


func present(parent: VBoxContainer, view: GameView, media: ClassicMediaCatalog, text_scale: float) -> void:
	if parent == null or view == null:
		return
	_view = view
	_media = media
	_text_scale = maxf(0.1, text_scale)
	var any_spells := false
	if view.party_summary != null:
		_add_section_heading(parent, "Field spellbook", "Camped" if view.party_summary.camping else "Exploring")
	for character: CharacterView in view.party_members:
		_add_section_heading(parent, character.name, "SP %d/%d" % [character.spell_points, character.maximum_spell_points])
		_add_section_heading(parent, "Fast Spells", "Top-row 1–0 • Ctrl/Command-number casts")
		for binding: FastSpellBindingView in character.fast_spells:
			_add_fast_spell_row(parent, character, binding)
		for spell: SpellView in character.spells:
			any_spells = true
			_add_spell(parent, character, spell)
		_add_section_heading(parent, "%s's scroll case" % character.name, "Five fixed Classic slots")
		for scroll: SpellScrollView in character.scrolls:
			var scroll_row := HBoxContainer.new()
			scroll_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll_row.add_theme_constant_override("separation", 8)
			var scroll_label := _add_label(scroll_row, "Slot %d • %s%s" % [scroll.slot_index + 1, scroll.spell_name, "" if scroll.power == 0 else " • Power %d" % scroll.power], MUTED if scroll.power == 0 else Color("e0e2e5"), 13)
			scroll_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_add_intent_action(scroll_row, &"", "Use", scroll.use, PlayerIntent.use_scroll(character.id, scroll.slot_index))
			parent.add_child(scroll_row)
	if view.party_members.is_empty():
		_add_empty_state(parent, "No spellbooks", "The party has no characters.")
	elif not any_spells:
		_add_empty_state(parent, "No known spells", "No party member currently knows a spell.")


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
	var set_button := Button.new()
	set_button.text = "Set"
	set_button.disabled = not availability.enabled
	set_button.tooltip_text = availability.reason if set_button.disabled else "Store the selected spell and power in Fast Spell %s." % binding.shortcut_label
	set_button.pressed.connect(_set_fast_spell.bind(character.id, binding.slot_index, picker))
	row.add_child(set_button)
	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.disabled = binding.spell_id.is_empty() or not availability.enabled
	clear_button.tooltip_text = availability.reason if not availability.enabled else "" 
	clear_button.pressed.connect(_clear_fast_spell.bind(character.id, binding.slot_index))
	row.add_child(clear_button)
	parent.add_child(row)


func _add_spell(parent: VBoxContainer, character: CharacterView, spell: SpellView) -> void:
	var context := "Combat%s • Camp%s" % [" yes" if spell.castable_in_combat else " no", " yes" if spell.castable_in_camp else " no"]
	_add_content_card(parent, spell.icon_resource_type, spell.icon_id, spell.name, "%s • Cost %d" % [character.name, spell.cost], "%s\nRange %d–%d • Duration %d–%d • %s" % [spell.description, spell.range_min, spell.range_max, spell.duration_min, spell.duration_max, context])
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 5)
	if spell.power_levels.is_empty():
		_add_intent_action(row, &"spells.action.cast", "Cast", spell.field_cast, PlayerIntent.cast_spell(spell.id, character.id))
	else:
		for power: int in spell.power_levels:
			_add_intent_action(row, &"", "Cast P%d (%d SP)" % [power, absi(spell.cost * power)], spell.field_cast, PlayerIntent.cast_spell(spell.id, character.id, "", power))
	if spell.scroll_power_levels.is_empty():
		_add_intent_action(row, &"", "Make Scroll", spell.make_scroll, PlayerIntent.make_scroll(spell.id, character.id))
	else:
		for power: int in spell.scroll_power_levels:
			_add_intent_action(row, &"", "Make P%d Scroll (%d SP)" % [power, absi(spell.cost * power * 2)], spell.make_scroll, PlayerIntent.make_scroll(spell.id, character.id, power))
	var abort := ClassicBitmapButton.new()
	abort.configure({"id": &"spells.action.abort", "asset_id": &"spells.action.abort", "tooltip": "Abort", "accelerator": ""}, 1)
	abort.tooltip_text = "Return to exploration without casting."
	abort.command_requested.connect(func(_command_id: StringName) -> void: route_requested.emit(&"exploration"))
	row.add_child(abort)
	parent.add_child(row)


func _set_fast_spell(character_id: String, slot_index: int, picker: OptionButton) -> void:
	var selected: Variant = picker.get_selected_metadata()
	if not selected is Dictionary:
		return
	sound_requested.emit(144, false, false)
	intent_submitted.emit(PlayerIntent.set_fast_spell(character_id, slot_index, String(selected.get("spellId", "")), int(selected.get("power", 0))))


func _clear_fast_spell(character_id: String, slot_index: int) -> void:
	sound_requested.emit(144, false, false)
	intent_submitted.emit(PlayerIntent.set_fast_spell(character_id, slot_index))


func _add_intent_action(parent: Container, asset_id: StringName, label: String, availability: ActionAvailabilityView, intent: PlayerIntent) -> BaseButton:
	var button: BaseButton
	if not asset_id.is_empty() and not ClassicUiAssetCatalog.definition(asset_id).is_empty():
		var bitmap := ClassicBitmapButton.new()
		bitmap.configure({"id": asset_id, "asset_id": asset_id, "tooltip": label, "accelerator": ""}, 1)
		button = bitmap
	else:
		var text_button := Button.new()
		text_button.text = label
		text_button.custom_minimum_size = Vector2(64.0, 56.0)
		button = text_button
	button.disabled = availability == null or not availability.enabled
	button.tooltip_text = "Unavailable" if availability == null else availability.reason if not availability.enabled else label
	if not button.disabled:
		if button is ClassicBitmapButton:
			(button as ClassicBitmapButton).command_requested.connect(func(_command_id: StringName) -> void: intent_submitted.emit(intent))
		else:
			button.pressed.connect(func() -> void: intent_submitted.emit(intent))
	parent.add_child(button)
	return button


func _add_content_card(parent: Container, resource_type: String, icon_id: int, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(_content_icon(resource_type, icon_id))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	row.add_child(box)
	_add_label(box, title, Color("e7d078"), 17)
	_add_label(box, subtitle, Color("e0e2e5"))
	if not detail.is_empty():
		_add_label(box, detail, MUTED)
	parent.add_child(panel)


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
