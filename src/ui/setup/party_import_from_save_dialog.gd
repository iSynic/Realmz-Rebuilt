## Presents detached save-party sources and per-character review cards supplied by the host.
class_name PartyImportFromSaveDialog
extends Control

signal source_requested(index: int)
signal external_source_requested(path: String)
signal import_selected_requested(indices: Array[int])
signal cancel_requested
signal refresh_requested
signal adopt_changed_requested(adopt: bool)

@export var source_row_scene: PackedScene
@export var candidate_card_scene: PackedScene

const ANDROID_PREVIEW_SAVE_REASON := "External save browsing is unavailable in the Android preview. Use saves in this installation."
const SUBTITLE := "Choose a saved adventure. Its characters and their possessions come with them; the world stays behind."

@onready var _dialog_panel: PanelContainer = %Dialog
@onready var _phase_label: Label = %PhaseLabel
@onready var _subtitle: Label = %Subtitle
@onready var _source_actions: Control = %SourceActions
@onready var _browse_button: Button = %BrowseExternalSave
@onready var _refresh_button: Button = %RefreshSources
@onready var _capacity: Control = %ImportCapacity
@onready var _capacity_count: Label = %CapacityCount
@onready var _error_banner: Control = %ErrorBanner
@onready var _error_title: Label = %ErrorTitle
@onready var _message_label: Label = %MessageLabel
@onready var _sources_scroll: ScrollContainer = %SourcesScroll
@onready var _ready_heading: Label = %ReadyHeading
@onready var _ready_list: VBoxContainer = %ReadyList
@onready var _unusable_rule: Control = %UnusableRule
@onready var _unusable_heading: Label = %UnusableHeading
@onready var _unusable_list: VBoxContainer = %UnusableList
@onready var _empty_sources: Control = %EmptySources
@onready var _loading_state: Control = %LoadingState
@onready var _reading_label: Label = %ReadingLabel
@onready var _candidate_scroll: ScrollContainer = %CandidateScroll
@onready var _candidate_list: VBoxContainer = %CandidateList
@onready var _adopt_panel: Control = %AdoptPanel
@onready var _adopt_changed: CheckBox = %AdoptChangedItems
@onready var _adopt_detail: Label = %AdoptDetail
@onready var _left_behind_panel: Control = %LeftBehindPanel
@onready var _left_behind_list: Label = %LeftBehindList
@onready var _back_button: Button = %BackToSaves
@onready var _cancel_button: Button = %CancelImport
@onready var _import_button: Button = %ImportSelected
## The file browser is built the first time it is opened; it is 160 nodes that most sessions never use.
var _external_dialog: FileDialog

var _view: Dictionary = {}
var _phase := "selection"
var _selected_indices: Array[int] = []
var _cards: Array[PartyImportCandidateCard] = []
var _source_rows: Array[PartyImportSourceRow] = []
var _available_slots: int = 0


func _ready() -> void:
	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	_back_button.pressed.connect(func() -> void: refresh_requested.emit())
	_browse_button.pressed.connect(_open_external_save_picker)
	_refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	_import_button.pressed.connect(_submit_selected)
	_adopt_changed.toggled.connect(func(pressed: bool) -> void: adopt_changed_requested.emit(pressed))
	get_viewport().size_changed.connect(_refresh_visible_geometry)
	visible = false


func show_party_import(view: Dictionary) -> void:
	_view = view.duplicate(true)
	_phase = String(_view.get("phase", "selection"))
	_available_slots = maxi(0, int(_view.get("available_slots", 0)))
	var keep_adopt_focus := _adopt_changed.has_focus()
	_update_dialog_size()
	_render()
	visible = true
	if keep_adopt_focus and _adopt_panel.visible: _adopt_changed.grab_focus()
	else: _grab_initial_focus()


func close_party_import() -> void:
	visible = false
	if _external_dialog != null and _external_dialog.visible:
		_external_dialog.hide()


func focus_root() -> Node:
	return _external_dialog if _external_dialog != null and _external_dialog.visible else self


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_update_dialog_size()


func _open_external_save_picker() -> void:
	if OS.has_feature("android"):
		return
	_external_files().popup_centered(_fit_scaled_size(Vector2(900.0, 620.0)))


func _fit_scaled_size(preferred: Vector2) -> Vector2i:
	var scale := _ui_scale()
	var viewport_size := get_viewport_rect().size
	var margin := 48.0 * scale
	var available := Vector2(maxf(1.0, viewport_size.x - margin), maxf(1.0, viewport_size.y - margin))
	var target := (preferred * scale).min(available)
	return Vector2i(maxi(1, roundi(target.x)), maxi(1, roundi(target.y)))


func _ui_scale() -> float:
	var profile := UiSizing.profile_for(self)
	return profile.ui_scale if profile != null else 1.0


func _update_dialog_size() -> void:
	if _dialog_panel != null:
		_dialog_panel.custom_minimum_size = _fit_scaled_size(Vector2(1040.0, 640.0))


func _refresh_visible_geometry() -> void:
	if visible:
		_update_dialog_size()


func _render() -> void:
	var review := _phase == "review"
	_phase_label.text = "Choose who joins" if review else "Import party from save"
	var context: Array[String] = []
	for key: String in ["source_line", "destination"]:
		if not String(_view.get(key, "")).is_empty(): context.append(String(_view.get(key)))
	_subtitle.text = "   ·   ".join(context) if review else SUBTITLE
	_source_actions.visible = not review
	_capacity.visible = review
	_render_error()
	_render_sources()
	_loading_state.visible = _phase == "loading"
	_reading_label.text = String(_view.get("reading", "Reading the save…"))
	_candidate_scroll.visible = review
	_render_candidates()
	_render_review_extras(review)
	_back_button.visible = review or _phase == "loading"
	_back_button.text = "Choose another save" if review else "Back to saves"
	_import_button.visible = review
	_refresh_button.disabled = _phase == "loading"
	_browse_button.disabled = _phase == "loading" or OS.has_feature("android")
	_browse_button.tooltip_text = ANDROID_PREVIEW_SAVE_REASON if OS.has_feature("android") else "Import from a save file outside this installation."
	_update_selection_state()
	_link_focus()


func _render_error() -> void:
	var message := String(_view.get("message", "")) if _phase == "error" else String(_view.get("error", ""))
	_error_banner.visible = not message.is_empty()
	_error_title.text = String(_view.get("error_title", "Couldn't import those characters"))
	_message_label.text = message


func _render_sources() -> void:
	_clear(_ready_list)
	_clear(_unusable_list)
	_source_rows.clear()
	var listing := _phase in ["selection", "error"]
	_sources_scroll.visible = listing
	var sources: Array = _view.get("sources", []) if listing else []
	var ready_count := 0
	for index: int in sources.size():
		var source: Dictionary = sources[index] if sources[index] is Dictionary else {}
		var row := source_row_scene.instantiate() as PartyImportSourceRow
		row.name = "SaveSource%d" % index
		var usable := bool(source.get("valid", false))
		(_ready_list if usable else _unusable_list).add_child(row)
		row.bind(source, false)
		row.pressed.connect(func() -> void: source_requested.emit(index))
		_source_rows.append(row)
		if usable: ready_count += 1
	var unusable_count := sources.size() - ready_count
	_ready_heading.text = "Ready to import · %d" % ready_count
	_ready_heading.visible = ready_count > 0
	_unusable_heading.text = "Can't be imported · %d" % unusable_count
	_unusable_heading.visible = unusable_count > 0
	_unusable_rule.visible = ready_count > 0 and unusable_count > 0
	_empty_sources.visible = listing and sources.is_empty()


func _render_candidates() -> void:
	_clear(_candidate_list)
	_cards.clear()
	_selected_indices.clear()
	if _phase != "review":
		return
	var candidates: Array = _view.get("candidates", [])
	for index: int in candidates.size():
		var candidate: Dictionary = candidates[index] if candidates[index] is Dictionary else {}
		if bool(candidate.get("selected", false)) and bool(candidate.get("eligible", false)) and _selected_indices.size() < _available_slots:
			_selected_indices.append(index)
		var card := candidate_card_scene.instantiate() as PartyImportCandidateCard
		_candidate_list.add_child(card)
		card.bind(candidate, index)
		card.toggled.connect(_card_toggled.bind(index))
		_cards.append(card)


func _render_review_extras(review: bool) -> void:
	var changed := _strings(_view.get("changed_items", []))
	_adopt_panel.visible = review and not changed.is_empty()
	_adopt_changed.set_pressed_no_signal(bool(_view.get("adopt_changed", false)))
	_adopt_changed.text = "Bring this adventure's version of the changed item" if changed.size() == 1 else "Bring this adventure's versions of %d changed items" % changed.size()
	_adopt_detail.text = "This adventure redefines %s. Off leaves them behind; on brings this adventure's version, unequipped." % _and_list(changed)
	_adopt_changed.tooltip_text = _adopt_detail.text
	# The compact dialog keeps the character list tall; the explanation stays in the tooltip.
	_adopt_detail.visible = _dialog_panel.custom_minimum_size.x >= 900.0 * _ui_scale()
	var left_behind := _strings(_view.get("left_behind", []))
	_left_behind_panel.visible = review and not left_behind.is_empty()
	_left_behind_list.text = "  ".join(left_behind)


func _card_toggled(pressed: bool, index: int) -> void:
	if pressed and not _selected_indices.has(index) and _selected_indices.size() < _available_slots:
		_selected_indices.append(index)
	elif not pressed:
		_selected_indices.erase(index)
	_selected_indices.sort()
	_update_selection_state()


## Applies the slot cap: at the cap, unchecked cards explain why they can't be added.
func _update_selection_state() -> void:
	var at_cap := _selected_indices.size() >= _available_slots
	var eligible := 0
	var candidates: Array = _view.get("candidates", [])
	for card: PartyImportCandidateCard in _cards:
		var candidate: Dictionary = candidates[card.index]
		var selected := _selected_indices.has(card.index)
		var reason := ""
		if not bool(candidate.get("eligible", false)):
			var reasons: Array = candidate.get("reasons", [])
			reason = String(reasons[0]) if not reasons.is_empty() else "This character can't join this party."
		else:
			eligible += 1
			if _available_slots == 0: reason = "The party is full."
			elif at_cap and not selected: reason = "All %d open slots are chosen." % _available_slots
		card.set_choice(selected, reason)
	_capacity_count.text = "%d of %d" % [_selected_indices.size(), _available_slots]
	var count := _selected_indices.size()
	_import_button.disabled = count == 0
	_import_button.text = "Import %d %s" % [count, "character" if count == 1 else "characters"] if count > 0 else "Import characters"
	if _available_slots == 0: _import_button.tooltip_text = "The party is full. Remove a character in party setup first."
	elif eligible == 0: _import_button.tooltip_text = "Nobody in this save can join. Choose another save."
	else: _import_button.tooltip_text = "Choose at least one character." if count == 0 else "Add the chosen characters to the party."


## One vertical chain per phase; the footer buttons sit side by side beneath it.
func _link_focus() -> void:
	var chain: Array[Control] = []
	match _phase:
		"review":
			chain.append_array(_cards)
			if _adopt_panel.visible: chain.append(_adopt_changed)
		"loading":
			pass
		_:
			chain.append_array([_browse_button, _refresh_button] if not _browse_button.disabled else [_refresh_button])
			chain.append_array(_source_rows)
	chain.append(_import_button if _phase == "review" and not _import_button.disabled else _back_button if _back_button.visible else _cancel_button)
	for index: int in chain.size():
		var control := chain[index]
		control.focus_neighbor_top = control.get_path_to(chain[wrapi(index - 1, 0, chain.size())])
		control.focus_neighbor_bottom = control.get_path_to(chain[wrapi(index + 1, 0, chain.size())])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom
	var above := chain[maxi(0, chain.size() - 2)]
	for button: Button in [_back_button, _cancel_button, _import_button]:
		if not chain.has(button):
			button.focus_neighbor_top = button.get_path_to(above)


func _grab_initial_focus() -> void:
	var target: Control = _cancel_button
	match _phase:
		"review":
			target = _cards[0] if not _cards.is_empty() else _back_button
		"loading":
			target = _back_button
		_:
			if not _source_rows.is_empty():
				target = _source_rows[0]
			elif not _browse_button.disabled:
				target = _browse_button
			else:
				target = _refresh_button
	if target.is_inside_tree() and target.visible:
		target.grab_focus()


func _submit_selected() -> void:
	if _selected_indices.is_empty() or _selected_indices.size() > _available_slots:
		return
	var indices: Array[int] = _selected_indices.duplicate()
	import_selected_requested.emit(indices)


## Escape steps back one level: review and reading return to the save list, which cancels.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if _phase in ["review", "loading"]:
		refresh_requested.emit()
	else:
		cancel_requested.emit()
	get_viewport().set_input_as_handled()


static func _and_list(values: Array[String]) -> String:
	if values.size() <= 1:
		return "".join(values)
	return "%s and %s" % [", ".join(values.slice(0, values.size() - 1)), values[-1]]


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


func _external_files() -> FileDialog:
	if _external_dialog != null:
		return _external_dialog
	_external_dialog = FileDialog.new()
	_external_dialog.name = "ExternalSaveDialog"
	_external_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	_external_dialog.size = Vector2i(900, 620)
	_external_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_external_dialog.title = "Choose a saved adventure"
	_external_dialog.ok_button_text = "Open"
	_external_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_external_dialog.filters = PackedStringArray(["*.r2save ; Realmz Rebuilt Saved Adventure"])
	_external_dialog.use_native_dialog = false
	add_child(_external_dialog)
	_external_dialog.file_selected.connect(func(path: String) -> void: external_source_requested.emit(path))
	return _external_dialog
