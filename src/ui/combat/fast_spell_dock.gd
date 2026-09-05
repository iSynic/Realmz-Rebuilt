## Presents the dynamic fast spell dock interaction without owning gameplay state.

class_name FastSpellDock
extends PanelContainer

signal slot_activated(slot_index: int)

const FRAME_DURATION_SECONDS := 0.12
const DOCK_HEIGHT := 76.0
const MIN_SLOT_WIDTH := 44.0
const MAX_SLOT_WIDTH := 68.0
const SLOT_SEPARATION := 4.0
const SLOT_SCENE_PATH := "res://src/ui/combat/fast_spell_dock_slot.tscn"

var _stage_rect := Rect2()
var _row: HBoxContainer
var _buttons: Array[Button] = []
var _slots: Array[FastSpellDockSlot] = []
var _frames_by_entry: Array = []
var _frame_index := 0
var _frame_elapsed := 0.0
var _has_assigned_binding := false


func _ready() -> void:
	_bind_scene_nodes()
	set_process(false)


func _bind_scene_nodes() -> void:
	if _row == null:
		_row = get_node("FastSpellDockSlots") as HBoxContainer


func configure(bindings: Array[InteractionRequestValue.FastSpell], animation_frames: Dictionary) -> void:
	_bind_scene_nodes()
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
	for index: int in _slots.size():
		var frames: Array = _frames_by_entry[index]
		if not frames.is_empty():
			_slots[index].set_preview_texture(frames[_frame_index % frames.size()] as Texture2D)


func _add_binding(slot_index: int, binding: InteractionRequestValue.FastSpell, frames: Array) -> void:
	var button := (load(SLOT_SCENE_PATH) as PackedScene).instantiate() as FastSpellDockSlot
	button.name = "FastSpellDockSlot%d" % slot_index
	_row.add_child(button)
	button.configure(slot_index, binding, frames)
	button.pressed.connect(func() -> void: slot_activated.emit(slot_index))
	_buttons.append(button)
	_slots.append(button)
	_frames_by_entry.append(frames)


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
	_slots.clear()
	_frames_by_entry.clear()
	_frame_index = 0
	_frame_elapsed = 0.0
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
