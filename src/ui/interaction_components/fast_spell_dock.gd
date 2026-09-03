class_name FastSpellDock
extends PanelContainer

signal slot_activated(slot_index: int)

const FRAME_DURATION_SECONDS := 0.12
const DOCK_HEIGHT := 76.0
const MIN_SLOT_WIDTH := 44.0
const MAX_SLOT_WIDTH := 68.0
const SLOT_SEPARATION := 4.0

var _stage_rect := Rect2()
var _row: HBoxContainer
var _buttons: Array[Button] = []
var _previews: Array[TextureRect] = []
var _frames_by_entry: Array = []
var _frame_index := 0
var _frame_elapsed := 0.0
var _has_assigned_binding := false


func _init() -> void:
	name = "FastSpellDock"
	theme_type_variation = &"ClassicInset"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90
	visible = false
	set_process(false)
	_row = HBoxContainer.new()
	_row.name = "FastSpellDockSlots"
	_row.add_theme_constant_override("separation", int(SLOT_SEPARATION))
	add_child(_row)


func configure(bindings: Array[InteractionRequestValue.FastSpell], animation_frames: Dictionary) -> void:
	_clear_entries()
	_has_assigned_binding = false
	for slot_index: int in mini(10, bindings.size()):
		var binding := bindings[slot_index]
		if binding.spell_id.is_empty():
			continue
		_has_assigned_binding = true
		_add_binding(slot_index, binding, animation_frames.get(binding.spell_id, []) as Array)
	_apply_layout()


func set_stage_rect(stage_rect: Rect2) -> void:
	_stage_rect = stage_rect
	_apply_layout()


func set_held(held: bool) -> bool:
	visible = held and _has_assigned_binding and not _buttons.is_empty()
	set_process(visible)
	if visible:
		_frame_elapsed = 0.0
	return _has_assigned_binding


func has_assigned_binding() -> bool:
	return _has_assigned_binding


func _process(delta: float) -> void:
	_frame_elapsed += delta
	if _frame_elapsed < FRAME_DURATION_SECONDS:
		return
	_frame_elapsed = fmod(_frame_elapsed, FRAME_DURATION_SECONDS)
	_frame_index += 1
	for index: int in _previews.size():
		var frames: Array = _frames_by_entry[index]
		if not frames.is_empty():
			_previews[index].texture = frames[_frame_index % frames.size()] as Texture2D


func _add_binding(slot_index: int, binding: InteractionRequestValue.FastSpell, frames: Array) -> void:
	var button := Button.new()
	button.name = "FastSpellDockSlot%d" % slot_index
	button.theme_type_variation = &"ClassicTheldrowButton"
	button.disabled = not binding.enabled
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "%s • Power %d%s" % [binding.spell_name, binding.power, "" if binding.enabled else " • %s" % binding.reason]
	button.pressed.connect(func() -> void: slot_activated.emit(slot_index))
	_row.add_child(button)
	_buttons.append(button)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	content.add_theme_constant_override("separation", 0)
	button.add_child(content)

	var preview := TextureRect.new()
	preview.name = "FastSpellDockPreview%d" % slot_index
	preview.custom_minimum_size = Vector2(0.0, 42.0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not frames.is_empty():
		preview.texture = frames[0] as Texture2D
	content.add_child(preview)
	_previews.append(preview)
	_frames_by_entry.append(frames)

	var key_label := Label.new()
	key_label.name = "FastSpellDockKey%d" % slot_index
	key_label.text = "%s · P%d" % ["0" if slot_index == 9 else str(slot_index + 1), binding.power]
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.add_theme_color_override("font_color", Color("f0ce59") if binding.enabled else Color("8c8170"))
	content.add_child(key_label)


func _apply_layout() -> void:
	if _stage_rect.size.x <= 0.0 or _buttons.is_empty():
		return
	var count := _buttons.size()
	var available_width := maxf(1.0, _stage_rect.size.x - 24.0 - SLOT_SEPARATION * float(count - 1))
	var slot_width := clampf(floorf(available_width / float(count)), MIN_SLOT_WIDTH, MAX_SLOT_WIDTH)
	for button: Button in _buttons:
		button.custom_minimum_size = Vector2(slot_width, DOCK_HEIGHT - 10.0)
	var dock_width := slot_width * float(count) + SLOT_SEPARATION * float(count - 1) + 12.0
	size = Vector2(dock_width, DOCK_HEIGHT)
	position = Vector2(_stage_rect.position.x + (_stage_rect.size.x - dock_width) * 0.5, _stage_rect.end.y - DOCK_HEIGHT - 8.0)


func _clear_entries() -> void:
	_buttons.clear()
	_previews.clear()
	_frames_by_entry.clear()
	_frame_index = 0
	_frame_elapsed = 0.0
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
