## Presents detached save-party sources and candidate reviews supplied by the host.
class_name PartyImportFromSaveDialog
extends Control

signal source_requested(index: int)
signal external_source_requested(path: String)
signal import_selected_requested(indices: Array[int])
signal cancel_requested
signal refresh_requested

@export var source_row_scene: PackedScene
@export var candidate_row_scene: PackedScene
@export var detail_label_scene: PackedScene

const ERROR_COLOR := Color("ef7770")
const MUTED_COLOR := Color("9aa0a8")

@onready var _empty_sources: Label = %EmptySources
@onready var _loading_source: Label = %LoadingSource
@onready var _capacity: Label = %ImportCapacity
@onready var _phase_label: Label = %PhaseLabel
@onready var _dialog_panel: PanelContainer = %Dialog
@onready var _message_label: Label = %MessageLabel
@onready var _sources_heading: Label = %SourcesHeading
@onready var _sources_scroll: ScrollContainer = %SourcesScroll
@onready var _sources_list: VBoxContainer = %SourcesList
@onready var _candidate_heading: Label = %CandidateHeading
@onready var _candidate_scroll: ScrollContainer = %CandidateScroll
@onready var _candidate_list: VBoxContainer = %CandidateList
@onready var _left_behind_panel: PanelContainer = %LeftBehindPanel
@onready var _left_behind_list: VBoxContainer = %LeftBehindList
@onready var _selection_actions: HBoxContainer = %SelectionActions
@onready var _review_actions: HBoxContainer = %ReviewActions
@onready var _browse_button: Button = %BrowseExternalSave
@onready var _refresh_button: Button = %RefreshSources
@onready var _import_button: Button = %ImportSelected
@onready var _cancel_button: Button = %CancelImport
@onready var _selection_cancel_button: Button = %CancelSelection
@onready var _external_dialog: FileDialog = %ExternalSaveDialog

var _view: Dictionary = {}
var _selected_indices: Array[int] = []
var _candidate_checks: Array[CheckBox] = []
var _candidate_details: Array[String] = []
var _available_slots: int = 0
var _selection_limit_message: String = ""


func _ready() -> void:
	_cancel_button.pressed.connect(_cancel)
	_selection_cancel_button.pressed.connect(_cancel)
	_browse_button.pressed.connect(_external_dialog.popup_centered)
	_refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	_import_button.pressed.connect(_submit_selected)
	_external_dialog.file_selected.connect(func(path: String) -> void: external_source_requested.emit(path))
	visible = false


func show_party_import(view: Dictionary) -> void:
	_view = view.duplicate(true)
	_available_slots = maxi(0, int(_view.get("available_slots", 0)))
	_selection_limit_message = ""
	var stage_size := get_viewport_rect().size
	_dialog_panel.custom_minimum_size = Vector2(minf(1040.0, maxf(760.0, stage_size.x - 48.0)), minf(640.0, maxf(520.0, stage_size.y - 48.0)))
	_render()
	visible = true
	_grab_initial_focus()


func close_party_import() -> void:
	visible = false
	if _external_dialog.visible:
		_external_dialog.hide()


func focus_root() -> Node:
	return _external_dialog if _external_dialog.visible else self


func _render() -> void:
	_clear(_sources_list)
	_clear(_candidate_list)
	_clear(_left_behind_list)
	_candidate_checks.clear()
	_candidate_details.clear()
	_selected_indices.clear()
	var phase := String(_view.get("phase", "selection"))
	_phase_label.text = _phase_title(phase)
	_message_label.text = _selection_limit_message if not _selection_limit_message.is_empty() else String(_view.get("message", ""))
	_message_label.modulate = ERROR_COLOR if phase == "error" or not _selection_limit_message.is_empty() else MUTED_COLOR
	_sources_heading.visible = phase == "selection" or phase == "loading" or phase == "error"
	_sources_scroll.visible = _sources_heading.visible
	_candidate_heading.visible = phase == "review"
	_candidate_scroll.visible = phase == "review"
	_left_behind_panel.visible = phase == "review" and not _strings(_view.get("left_behind", [])).is_empty()
	_selection_actions.visible = phase == "selection" or phase == "loading" or phase == "error"
	_review_actions.visible = phase == "review"
	_refresh_button.disabled = phase == "loading"
	_browse_button.disabled = phase == "loading"
	var sources: Array = _view.get("sources", [])
	_empty_sources.visible = sources.is_empty() and phase == "selection"
	_loading_source.visible = phase == "loading"
	_capacity.visible = phase == "review"
	for index: int in sources.size():
		var source: Dictionary = sources[index] if sources[index] is Dictionary else {}
		var row := source_row_scene.instantiate()
		var button := row.get_node("Source") as Button
		button.name = "SaveSource%d" % index
		button.text = String(source.get("label", "Save %d" % (index + 1)))
		button.tooltip_text = String(source.get("detail", ""))
		button.disabled = not bool(source.get("valid", false)) or phase == "loading"
		_bind_detail(row.get_node("Detail"), String(source.get("detail", "")), button.disabled)
		_sources_list.add_child(row)
		button.pressed.connect(_request_source.bind(index))
	if phase == "review":
		_render_candidates(_view.get("candidates", []))
		for warning: String in _strings(_view.get("left_behind", [])):
			_left_behind_list.add_child(_detail_label(warning, false))
	_update_import_button()
	_link_vertical_focus()


func _link_vertical_focus() -> void:
	var controls: Array[Control] = []
	if String(_view.get("phase", "")) == "review":
		for check: CheckBox in _candidate_checks:
			if not check.disabled: controls.append(check)
		controls.append_array([_cancel_button, _import_button])
	else:
		for row: Node in _sources_list.get_children():
			var button := row.get_child(0) as Button if row.get_child_count() > 0 else null
			if button != null and not button.disabled: controls.append(button)
		controls.append_array([_browse_button, _refresh_button, _selection_cancel_button])
	for index: int in controls.size():
		var control := controls[index]
		control.focus_neighbor_top = control.get_path_to(controls[wrapi(index - 1, 0, controls.size())])
		control.focus_neighbor_bottom = control.get_path_to(controls[wrapi(index + 1, 0, controls.size())])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom


func _render_candidates(raw_candidates: Variant) -> void:
	var candidates: Array = raw_candidates if raw_candidates is Array else []
	var incoming_selected := false
	for candidate: Variant in candidates:
		if candidate is Dictionary and bool(candidate.get("selected", false)) and bool(candidate.get("eligible", false)):
			incoming_selected = true
			break
	for index: int in candidates.size():
		var candidate: Dictionary = candidates[index] if candidates[index] is Dictionary else {}
		var eligible := bool(candidate.get("eligible", false))
		var selected := bool(candidate.get("selected", false)) and eligible
		if not incoming_selected and eligible and _selected_indices.size() < _available_slots:
			selected = true
		if selected and _selected_indices.size() >= _available_slots:
			selected = false
		if selected:
			_selected_indices.append(index)
		var row := candidate_row_scene.instantiate()
		var check := row.get_node("Candidate") as CheckBox
		check.name = "Candidate%d" % index
		check.text = String(candidate.get("name", "Character %d" % (index + 1)))
		check.button_pressed = selected
		check.disabled = not eligible or _available_slots == 0
		check.toggled.connect(_candidate_toggled.bind(index))
		var detail_text := String(candidate.get("detail", ""))
		if not eligible and detail_text.is_empty():
			detail_text = "This character cannot join the selected party."
		_bind_detail(row.get_node("Detail"), detail_text, not eligible)
		_candidate_list.add_child(row)
		_candidate_checks.append(check)
		_candidate_details.append(detail_text)
	_update_capacity()


func _candidate_toggled(pressed: bool, index: int) -> void:
	if pressed and not _selected_indices.has(index) and _selected_indices.size() >= _available_slots:
		_candidate_checks[index].set_pressed_no_signal(false)
		_selection_limit_message = "Choose up to %d characters for the available party slots." % _available_slots
		_message_label.text = _selection_limit_message
		_message_label.modulate = ERROR_COLOR
		_update_import_button()
		return
	if pressed:
		if not _selected_indices.has(index):
			_selected_indices.append(index)
	else:
		_selected_indices.erase(index)
	_selected_indices.sort()
	_selection_limit_message = ""
	_message_label.text = String(_view.get("message", ""))
	_message_label.modulate = MUTED_COLOR
	_update_capacity()
	_update_import_button()


func _update_import_button() -> void:
	_import_button.disabled = _selected_indices.is_empty() or _selected_indices.size() > _available_slots
	_import_button.text = "Import %d selected" % _selected_indices.size() if not _selected_indices.is_empty() else "Import selected"


func _submit_selected() -> void:
	if _selected_indices.is_empty() or _selected_indices.size() > _available_slots:
		return
	var indices: Array[int] = _selected_indices.duplicate()
	import_selected_requested.emit(indices)


func _request_source(index: int) -> void:
	source_requested.emit(index)


func _cancel() -> void:
	cancel_requested.emit()


func _grab_initial_focus() -> void:
	var phase := String(_view.get("phase", "selection"))
	var target: Control = _selection_cancel_button
	if phase == "review":
		target = _candidate_checks[0] if not _candidate_checks.is_empty() and not _candidate_checks[0].disabled else _cancel_button
	elif phase != "loading":
		for row: Node in _sources_list.get_children():
			if row.get_child_count() == 0:
				continue
			var source_button := row.get_child(0) as Button
			if source_button != null and not source_button.disabled:
				target = source_button
				break
		if target == _selection_cancel_button and not _browse_button.disabled:
			target = _browse_button
	elif not _selection_cancel_button.disabled:
		target = _selection_cancel_button
	if target.is_inside_tree() and target.visible and target.focus_mode != Control.FOCUS_NONE and not target.disabled:
		target.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()


func _phase_title(phase: String) -> String:
	match phase:
		"loading": return "Reading saved party"
		"review": return "Review characters to import"
		"error": return "Could not read saved party"
		_: return "Import party from save"


func _detail_label(text: String, is_error: bool) -> Label:
	var label := detail_label_scene.instantiate() as Label
	_bind_detail(label, text, is_error)
	return label


func _bind_detail(label: Label, text: String, is_error: bool) -> void:
	label.text = text
	label.visible = not text.is_empty()
	label.modulate = ERROR_COLOR if is_error else MUTED_COLOR


func _update_capacity() -> void:
	_capacity.text = "%d of %d party slots selected" % [_selected_indices.size(), _available_slots]


func _strings(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item: Variant in value:
			result.append(String(item))
	return result


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
