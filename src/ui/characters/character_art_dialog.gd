## Binds the race-first artwork library; the host owns decoding and persistence.
class_name CharacterArtDialog
extends Control

signal opened
signal sources_requested(paths: PackedStringArray, kind: String, folder: bool)
signal preview_requested(index: int, mode: String, filter: String, crop: Rect2i)
signal batch_item_selected(index: int)
signal import_requested
signal batch_cancelled
signal group_created(name: String)
signal group_renamed(name: String, replacement: String)
signal group_removed(name: String)
signal image_renamed(group: String, id: String, label: String)
signal images_removed(group: String, ids: PackedStringArray)
signal artwork_selected(asset_id: String, kind: String)
signal dismissed

var selected_group := ""
var _groups: Array[Dictionary] = []
var _entries: Array[Dictionary] = []
var _visible_entries: Array[Dictionary] = []
var _batch := false
var _binding := false
var _batch_index := -1
var _source_size := Vector2i.ZERO
var _preview_texture: Texture2D
var _pick_kind := "portrait"
var _name_action := ""
var _remove_group := false
var _selection_callback := Callable()
var _focus_before_open: WeakRef


func _ready() -> void:
	(%ArtRaces as ItemList).item_selected.connect(_select_group)
	(%LibraryEntries as ItemList).multi_selected.connect(_select_entry)
	(%NewRace as Button).pressed.connect(_prompt_name.bind("create"))
	(%RenameRace as Button).pressed.connect(_prompt_name.bind("group"))
	(%RenameImage as Button).pressed.connect(_prompt_name.bind("image"))
	(%RemoveRace as Button).pressed.connect(_prompt_removal.bind(true))
	(%RemoveImages as Button).pressed.connect(_prompt_removal.bind(false))
	(%NamePrompt as ConfirmationDialog).confirmed.connect(_save_name)
	(%NameInput as LineEdit).text_submitted.connect(func(_text: String) -> void:
		(%NamePrompt as ConfirmationDialog).hide()
		_save_name()
	)
	(%RemovePrompt as ConfirmationDialog).confirmed.connect(_remove_confirmed)
	for button: MenuButton in [%ImportIcons, %ImportPortraits]:
		button.get_popup().add_item("Choose images…", 0)
		button.get_popup().add_item("Choose folder…", 1)
		button.get_popup().id_pressed.connect(_open_picker.bind("combat-icon" if button == %ImportIcons else "portrait"))
	(%SourceFiles as FileDialog).files_selected.connect(func(paths: PackedStringArray) -> void: sources_requested.emit(paths, _pick_kind, false))
	(%SourceFiles as FileDialog).dir_selected.connect(func(path: String) -> void: sources_requested.emit(PackedStringArray([path]), _pick_kind, true))
	(%ArtMode as OptionButton).item_selected.connect(func(_index: int) -> void: _state_changed())
	(%ArtFilter as OptionButton).item_selected.connect(func(_index: int) -> void: _state_changed())
	for control: SpinBox in [%CropX, %CropY, %CropSize]:
		control.value_changed.connect(func(_value: float) -> void: _state_changed())
	(%ImportArt as Button).pressed.connect(func() -> void: import_requested.emit())
	(%CancelImport as Button).pressed.connect(func() -> void: batch_cancelled.emit())
	(%UseArtwork as Button).pressed.connect(_use_artwork)
	(%DoneArt as Button).pressed.connect(dismiss)
	for popup: Window in [%SourceFiles, %NamePrompt, %RemovePrompt]:
		popup.visibility_changed.connect(_update_popup_shield)
	(%PopupInputShield as Control).gui_input.connect(_handle_popup_shield_input)
	_update_actions()


func _update_popup_shield() -> void:
	# Native exclusivity blocks the outer compositor's input forwarding.
	(%PopupInputShield as Control).visible = (%SourceFiles as Window).visible or (%NamePrompt as Window).visible or (%RemovePrompt as Window).visible


func _handle_popup_shield_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		(%PopupInputShield as Control).accept_event()
		for popup: Window in [%SourceFiles, %NamePrompt, %RemovePrompt]:
			if popup.visible:
				popup.grab_focus()


func open_library(group_name: String = "", selection: Callable = Callable()) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_focus_before_open = weakref(focused) if focused != null else null
	selected_group = group_name
	_selection_callback = selection
	visible = true
	_fit()
	opened.emit()
	(%ArtRaces as ItemList).grab_focus()


func bind_library(groups: Array[Dictionary], entries: Array[Dictionary]) -> void:
	_groups = groups.duplicate()
	_entries = entries.duplicate()
	_batch = false
	_batch_index = -1
	var races := %ArtRaces as ItemList
	races.clear()
	var selected := -1
	for group: Dictionary in _groups:
		races.add_item(group.name)
		if String(group.name).nocasecmp_to(selected_group) == 0:
			selected = races.item_count - 1
	if selected < 0 and not _groups.is_empty():
		selected = 0
	if selected >= 0:
		races.select(selected)
		races.ensure_current_is_visible()
		_select_group(selected)
	else:
		selected_group = ""
		_refresh_entries()
	(%LibraryStatus as Label).text = "Choose a race to add portraits and icons. Artwork races do not change character rules."
	_update_actions()


func bind_batch(rows: Array[Dictionary], ready: int, busy: bool) -> void:
	_batch = true
	_visible_entries = rows.duplicate()
	var list := %LibraryEntries as ItemList
	list.clear()
	for row: Dictionary in rows:
		list.add_item(row.label + (" · skipped" if not String(row.error).is_empty() else ""), row.get("texture") as Texture2D)
		list.set_item_tooltip(list.item_count - 1, row.error)
	if _batch_index >= 0 and _batch_index < list.item_count:
		list.select(_batch_index)
	(%LibraryStatus as Label).text = "Preparing %d images…" % rows.size() if busy else "%d ready · %d skipped. Review each result, then import." % [ready, rows.size() - ready]
	(%ImportArt as Button).text = "Import %d images" % ready
	_update_actions()
	(%ImportArt as Button).disabled = busy or ready == 0


func bind_batch_item(index: int, filename: String, source_size: Vector2i, mode: String, filter: String, crop: Rect2i) -> void:
	_binding = true
	_batch_index = index
	_source_size = source_size
	(%SourceName as Label).text = filename
	(%SourceDimensions as Label).text = "%d × %d source" % [source_size.x, source_size.y]
	(%ArtMode as OptionButton).select(maxi(0, ["fit", "crop", "resize"].find(mode)))
	(%ArtFilter as OptionButton).select(0 if filter == "nearest" else 1)
	(%CropX as SpinBox).max_value = maxi(0, source_size.x - 1)
	(%CropY as SpinBox).max_value = maxi(0, source_size.y - 1)
	(%CropSize as SpinBox).max_value = mini(source_size.x, source_size.y)
	(%CropX as SpinBox).value = crop.position.x
	(%CropY as SpinBox).value = crop.position.y
	(%CropSize as SpinBox).value = crop.size.x
	_binding = false
	_update_actions()


func bind_preview(texture: Texture2D, error: String = "") -> void:
	_preview_texture = texture
	(%PreviewError as Label).text = error
	_size_preview()


func _size_preview() -> void:
	var side := _preview_texture.get_width() if _preview_texture != null else 44
	var native := %NativePreview as TextureRect
	var enlarged := %EnlargedPreview as TextureRect
	native.texture = _preview_texture
	enlarged.texture = _preview_texture
	native.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	enlarged.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	native.custom_minimum_size = Vector2(side, side)
	enlarged.custom_minimum_size = Vector2(side * 4, side * 4)
	(%NativeSize as Label).text = "%d × %d native" % [side, side]


func show_error(message: String) -> void:
	(%LibraryStatus as Label).text = message


func controller_focus_root() -> Node:
	for control: Window in [%SourceFiles, %NamePrompt, %RemovePrompt]:
		if control.visible:
			return control
	return self


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_size_preview()
	_fit.call_deferred()


func dismiss() -> void:
	for control: Window in [%SourceFiles, %NamePrompt, %RemovePrompt]:
		if control.visible:
			control.hide()
			return
	if _batch:
		batch_cancelled.emit()
		return
	hide()
	_selection_callback = Callable()
	var previous := _focus_before_open.get_ref() as Control if _focus_before_open != null else null
	_focus_before_open = null
	if previous != null and previous.is_visible_in_tree():
		previous.grab_focus()
	dismissed.emit()


func _select_group(index: int) -> void:
	if _batch or index < 0 or index >= _groups.size():
		return
	selected_group = _groups[index].name
	_refresh_entries()
	_update_actions()


func _refresh_entries() -> void:
	_visible_entries.clear()
	var list := %LibraryEntries as ItemList
	list.clear()
	(%SelectedRaceHeading as Label).text = selected_group if not selected_group.is_empty() else "Choose an artwork race"
	for entry: Dictionary in _entries:
		if String(entry.group).nocasecmp_to(selected_group) != 0:
			continue
		_visible_entries.append(entry)
		list.add_item("%s · %s" % [entry.label, "Portrait" if entry.kind == "portrait" else "Icon"], entry.get("texture") as Texture2D)
	bind_preview(null)
	(%SourceName as Label).text = "Select artwork to preview"
	(%SourceDimensions as Label).text = ""


func _select_entry(index: int, selected: bool) -> void:
	if _batch:
		if selected:
			(%LibraryEntries as ItemList).deselect_all()
			(%LibraryEntries as ItemList).select(index)
			batch_item_selected.emit(index)
		return
	if selected and index < _visible_entries.size():
		var entry := _visible_entries[index]
		(%SourceName as Label).text = entry.label
		(%SourceDimensions as Label).text = "Built-in artwork" if entry.get("builtin", false) else "Imported artwork"
		bind_preview(entry.get("texture") as Texture2D)
	_update_actions()


func _update_actions() -> void:
	var builtin := false
	for group: Dictionary in _groups:
		if group.name == selected_group:
			builtin = group.builtin
	(%ArtRaces as ItemList).mouse_filter = Control.MOUSE_FILTER_IGNORE if _batch else Control.MOUSE_FILTER_STOP
	(%ArtRaces as ItemList).focus_mode = Control.FOCUS_NONE if _batch else Control.FOCUS_ALL
	(%NewRace as Button).disabled = _batch
	(%RenameRace as Button).disabled = _batch or builtin or selected_group.is_empty()
	(%RemoveRace as Button).disabled = (%RenameRace as Button).disabled
	for button: MenuButton in [%ImportIcons, %ImportPortraits]:
		button.disabled = _batch or selected_group.is_empty()
	var indices := (%LibraryEntries as ItemList).get_selected_items()
	var editable := not indices.is_empty()
	for index: int in indices:
		editable = editable and not _visible_entries[index].get("builtin", false)
	(%RenameImage as Button).disabled = _batch or not editable or indices.size() != 1
	(%RemoveImages as Button).disabled = _batch or not editable
	(%UseArtwork as Button).visible = _selection_callback.is_valid() and not _batch
	(%UseArtwork as Button).disabled = indices.size() != 1
	(%SettingsRow as GridContainer).visible = _batch and _source_size != Vector2i.ZERO
	(%CropControls as HBoxContainer).visible = _batch and _source_size != Vector2i.ZERO and (%ArtMode as OptionButton).selected == 1
	(%CropHelp as Label).visible = _batch
	(%ImportArt as Button).visible = _batch
	(%CancelImport as Button).visible = _batch


func _open_picker(mode: int, kind: String) -> void:
	_pick_kind = kind
	var picker := %SourceFiles as FileDialog
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILES if mode == 0 else FileDialog.FILE_MODE_OPEN_DIR
	picker.title = "Import Portraits" if kind == "portrait" else "Import Icons"
	picker.popup_centered_ratio(0.88)
	picker.get_line_edit().grab_focus()


func _prompt_name(action: String) -> void:
	_name_action = action
	var input := %NameInput as LineEdit
	input.text = selected_group if action == "group" else ""
	if action == "image":
		input.text = _visible_entries[(%LibraryEntries as ItemList).get_selected_items()[0]].label
	(%NamePrompt as ConfirmationDialog).title = "New artwork race" if action == "create" else "Rename artwork race" if action == "group" else "Rename image"
	(%NamePrompt as ConfirmationDialog).popup_centered()
	input.grab_focus()
	input.select_all()


func _save_name() -> void:
	var name := (%NameInput as LineEdit).text.strip_edges()
	match _name_action:
		"create": group_created.emit(name)
		"group": group_renamed.emit(selected_group, name)
		"image": image_renamed.emit(selected_group, _visible_entries[(%LibraryEntries as ItemList).get_selected_items()[0]].id, name)


func _prompt_removal(group: bool) -> void:
	_remove_group = group
	var prompt := %RemovePrompt as ConfirmationDialog
	prompt.dialog_text = "Remove artwork race %s and its imported images from the library?" % selected_group if group else "Remove %d selected images from this artwork race?" % (%LibraryEntries as ItemList).get_selected_items().size()
	prompt.dialog_text += "\nExisting characters keep their selected artwork."
	prompt.popup_centered()


func _remove_confirmed() -> void:
	if _remove_group:
		group_removed.emit(selected_group)
	else:
		var ids := PackedStringArray()
		for index: int in (%LibraryEntries as ItemList).get_selected_items():
			ids.append(_visible_entries[index].id)
		images_removed.emit(selected_group, ids)


func _use_artwork() -> void:
	var selected := (%LibraryEntries as ItemList).get_selected_items()
	if selected.size() != 1:
		return
	var entry := _visible_entries[selected[0]]
	artwork_selected.emit(entry.id, entry.kind)
	if _selection_callback.is_valid():
		_selection_callback.call(entry.id, entry.kind)
	dismiss()


func _state_changed() -> void:
	if _binding or not _batch or _batch_index < 0:
		return
	_binding = true
	(%CropSize as SpinBox).max_value = maxi(1, mini(_source_size.x - int((%CropX as SpinBox).value), _source_size.y - int((%CropY as SpinBox).value)))
	_binding = false
	var mode: String = ["fit", "crop", "resize"][(%ArtMode as OptionButton).selected]
	(%CropHelp as Label).text = "Fit preserves proportions with transparent padding." if mode == "fit" else "Crop selects an integer square from the source." if mode == "crop" else "Resize fills the square and may distort proportions."
	_update_actions()
	var side := int((%CropSize as SpinBox).value)
	preview_requested.emit(_batch_index, mode, "nearest" if (%ArtFilter as OptionButton).selected == 0 else "lanczos", Rect2i(int((%CropX as SpinBox).value), int((%CropY as SpinBox).value), side, side))


func _fit() -> void:
	if not is_node_ready():
		return
	var profile := UiSizing.profile_for(self)
	var area := profile.application_rect if profile != null else Rect2(Vector2.ZERO, size)
	var scale := profile.ui_scale if profile != null else 1.0
	var compact := area.size.x < 1000.0 * scale
	(%ArtBody as BoxContainer).vertical = compact
	(%PreviewHeading as Label).visible = not compact
	(%SourceDimensions as Label).visible = not compact
	(%LibraryPanel as PanelContainer).custom_minimum_size = Vector2(0, 210 * scale) if compact else Vector2(540 * scale, 0)
	(%LibraryPanel as PanelContainer).size_flags_vertical = Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL
	var window := %ArtWindow as PanelContainer
	window.size = Vector2(minf(1160.0 * scale, area.size.x * 0.96), minf(650.0 * scale, area.size.y * 0.94))
	window.position = area.position + (area.size - window.size) * 0.5
	(%ArtRaces as ItemList).ensure_current_is_visible.call_deferred()
