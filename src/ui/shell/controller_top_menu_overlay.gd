## Draws the controller-owned top-menu entries inside the application viewport.
class_name ControllerTopMenuOverlay
extends Control

const ROW_SCENE := preload("res://src/ui/shell/controller_top_menu_row.tscn")

@onready var _panel: PanelContainer = %DropdownPanel
@onready var _heading: Label = %Heading
@onready var _entries_scroll: ScrollContainer = %EntriesScroll
@onready var _entries: VBoxContainer = %Entries
@onready var _reason: Label = %Reason


func present(heading: String, entries: Array[Dictionary], selected_index: int, heading_rect: Rect2) -> void:
	visible = true
	_heading.text = heading
	for child: Node in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	var selected_row: Control
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		var row := ROW_SCENE.instantiate() as Label
		row.text = "%s%s" % ["▶ " if index == selected_index else "  ", String(entry.get("label", ""))]
		if index == selected_index:
			row.add_theme_color_override(&"font_color", Color("f2cb58"))
		elif not String(entry.get("disabled_reason", "")).is_empty():
			row.add_theme_color_override(&"font_color", Color(0.52, 0.55, 0.56, 1.0))
		_entries.add_child(row)
		if index == selected_index:
			row.set_meta(&"controller_selected", true)
			selected_row = row
	var selected: Dictionary = entries[selected_index] if selected_index >= 0 and selected_index < entries.size() else {}
	_reason.text = String(selected.get("disabled_reason", ""))
	_reason.visible = not _reason.text.is_empty()
	_panel.size = Vector2(320.0, minf(62.0 + entries.size() * 25.0 + (46.0 if _reason.visible else 0.0), maxf(120.0, size.y - 38.0)))
	var local_anchor := heading_rect.position - global_position
	_panel.position = Vector2(clampf(local_anchor.x, 8.0, maxf(8.0, size.x - _panel.size.x - 8.0)), maxf(30.0, local_anchor.y + heading_rect.size.y))
	if selected_row != null:
		call_deferred("_reveal_current_selection")


func close() -> void:
	visible = false


func _reveal_current_selection() -> void:
	if not visible or _entries_scroll == null or _entries == null:
		return
	for child: Node in _entries.get_children():
		if child is Control and bool(child.get_meta(&"controller_selected", false)):
			_entries_scroll.ensure_control_visible(child as Control)
			return
