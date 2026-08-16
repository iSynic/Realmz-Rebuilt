class_name SystemWorkspaceController
extends RefCounted

const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")
const HeldMovementControllerScript := preload("res://src/presentation/held_movement_controller.gd")

signal action_requested(action_id: StringName, value: Variant)
signal setting_changed(setting_id: StringName, value: Variant)

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")

var _save_previews: Array[SaveSlotPreview] = []


func set_save_previews(previews: Array[SaveSlotPreview]) -> void:
	_save_previews = previews.duplicate()


func present(parent: VBoxContainer, view: GameView, settings: PresentationSettings) -> void:
	if parent == null or view == null or settings == null:
		return
	_add_card(parent, "Current campaign", view.campaign_summary.title if view.campaign_summary != null else view.campaign_id, "Package %s\nRules %s" % [view.campaign_summary.package_hash if view.campaign_summary != null else "Unavailable", view.rules_version])
	_add_section_heading(parent, "Save and restore", "Committed session boundaries only")
	var save_row := HBoxContainer.new()
	_add_action(save_row, "Quick save", &"save", "quick")
	_add_action(save_row, "Quick load", &"load", "quick")
	_add_action(save_row, "Campaign library", &"campaigns", null)
	var end_adventure := _add_action(save_row, "End adventure", &"end_adventure", null)
	end_adventure.disabled = view.pending_interaction != null and view.pending_interaction.kind != InteractionRequest.COMBAT
	end_adventure.tooltip_text = "Resolve the current interaction first." if end_adventure.disabled else "Close this campaign session without quitting Realmz Rebuilt."
	_add_action(save_row, "Refresh saves", &"refresh_saves", null)
	parent.add_child(save_row)
	_add_section_heading(parent, "Save slots", "%d record%s" % [_save_previews.size(), "" if _save_previews.size() == 1 else "s"])
	if _save_previews.is_empty():
		_add_card(parent, "No saves for this campaign", "Quick save creates the first validated slot.", "")
	else:
		for preview: SaveSlotPreview in _save_previews:
			_add_save_preview(parent, preview)
	_add_section_heading(parent, "Display", "Interface scale and text size are independent")
	var ui_scale := OptionButton.new()
	for entry: Dictionary in [{"label": "UI scale: Auto", "id": PresentationSettings.UI_SCALE_AUTO}, {"label": "UI scale: 100%", "id": PresentationSettings.UI_SCALE_100}, {"label": "UI scale: 125%", "id": PresentationSettings.UI_SCALE_125}, {"label": "UI scale: 150%", "id": PresentationSettings.UI_SCALE_150}]:
		ui_scale.add_item(entry["label"])
		ui_scale.set_item_metadata(ui_scale.item_count - 1, entry["id"])
		if entry["id"] == settings.ui_scale_mode:
			ui_scale.select(ui_scale.item_count - 1)
	ui_scale.item_selected.connect(func(index: int) -> void: setting_changed.emit(&"ui_scale_mode", String(ui_scale.get_item_metadata(index))))
	parent.add_child(ui_scale)
	var text_scale := HSlider.new()
	text_scale.min_value = 0.8
	text_scale.max_value = 1.5
	text_scale.step = 0.1
	text_scale.value = settings.text_scale
	text_scale.tooltip_text = "Text scale %d%%" % int(round(settings.text_scale * 100.0))
	text_scale.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"text_scale", value))
	parent.add_child(text_scale)
	var window_mode := OptionButton.new()
	window_mode.add_item("Windowed")
	window_mode.set_item_metadata(0, PresentationSettings.WINDOWED)
	window_mode.add_item("Borderless fullscreen")
	window_mode.set_item_metadata(1, PresentationSettings.BORDERLESS_FULLSCREEN)
	window_mode.select(1 if settings.window_mode == PresentationSettings.BORDERLESS_FULLSCREEN else 0)
	window_mode.item_selected.connect(func(index: int) -> void: setting_changed.emit(&"window_mode", String(window_mode.get_item_metadata(index))))
	parent.add_child(window_mode)
	var movement_row := HBoxContainer.new()
	var movement_label := _label("Exploration movement speed", MUTED, 14)
	movement_label.custom_minimum_size.x = 190.0
	movement_row.add_child(movement_label)
	var movement_speed := HSlider.new()
	movement_speed.min_value = 25.0
	movement_speed.max_value = 400.0
	movement_speed.step = 25.0
	movement_speed.value = settings.exploration_speed_percent
	movement_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	movement_speed.tooltip_text = "%d%% • %.3f seconds per held step" % [settings.exploration_speed_percent, HeldMovementControllerScript.BASE_INTERVAL_SECONDS * 100.0 / float(settings.exploration_speed_percent)]
	movement_speed.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"exploration_speed_percent", int(value)))
	movement_row.add_child(movement_speed)
	parent.add_child(movement_row)
	_add_section_heading(parent, "Accessibility and presentation", "These preferences never change simulation")
	_add_setting_toggle(parent, "Reduced motion", settings.reduced_motion, &"reduced_motion")
	_add_setting_toggle(parent, "Auto Switch To Melee Weapon", settings.auto_switch_to_melee, &"auto_switch_to_melee")
	_add_setting_toggle(parent, "Use topology-derived 3D dungeons", settings.dungeon_3d, &"dungeon_3d")
	_add_setting_toggle(parent, "Show topology diagnostics", settings.topology_debug, &"topology_debug")
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.05
	volume.value = settings.master_volume
	volume.tooltip_text = "Master volume"
	volume.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"master_volume", value))
	parent.add_child(volume)


func _add_action(parent: Container, label: String, action_id: StringName, value: Variant) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(func() -> void: action_requested.emit(action_id, value))
	parent.add_child(button)
	return button


func _add_save_preview(parent: VBoxContainer, preview: SaveSlotPreview) -> void:
	var party_text: String = ", ".join(preview.character_names) if not preview.character_names.is_empty() else "No party members"
	var detail: String = preview.error_message
	if preview.status == SaveSlotPreviewScript.VALID:
		detail = "Day %d • %02d:%02d • %s %d,%d\n%s\nPackage %s" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute, preview.map_id, preview.coordinate.x, preview.coordinate.y, party_text, preview.package_hash.left(12)]
	var card := VBoxContainer.new()
	_add_card(card, "%s • %s" % [preview.slot_id, preview.source_label()], "%s • %s" % [preview.status_label(), preview.rules_version if not preview.rules_version.is_empty() else "Unknown rules"], detail)
	var load_preview := Button.new()
	load_preview.text = "Load backup" if preview.source == SaveSlotPreviewScript.BACKUP else "Load save"
	load_preview.disabled = not preview.can_load
	load_preview.tooltip_text = preview.error_message if not preview.can_load else "Restore this validated %s record." % preview.source_label().to_lower()
	if preview.can_load:
		var action: StringName = &"load_backup" if preview.source == SaveSlotPreviewScript.BACKUP else &"load"
		load_preview.pressed.connect(func() -> void: action_requested.emit(action, preview.slot_id))
	card.add_child(load_preview)
	parent.add_child(card)


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


func _add_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	column.add_child(_label(title, GOLD, 16))
	if not subtitle.is_empty():
		column.add_child(_label(subtitle, MUTED, 13))
	if not detail.is_empty():
		var body := _label(detail, Color.WHITE, 14)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body)
	parent.add_child(panel)


func _add_setting_toggle(parent: Container, label: String, enabled: bool, setting_id: StringName) -> void:
	var toggle := CheckButton.new()
	toggle.text = label
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: setting_changed.emit(setting_id, value))
	parent.add_child(toggle)


func _label(text: String, color: Color, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", size)
	return result
