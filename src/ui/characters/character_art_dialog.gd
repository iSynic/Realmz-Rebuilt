## Presents character-art library and import controls; the host owns all file access and image work.
class_name CharacterArtDialog
extends Control

signal source_requested(path: String)
signal opened
signal preview_requested(kind: String, mode: String, filter: String, crop: Rect2i)
signal import_requested(group_name: String, label: String, kind: String, mode: String, filter: String, crop: Rect2i)
signal artwork_selected(asset_id: String, kind: String)
signal dismissed

const PORTRAIT := "portrait"
const COMBAT_ICON := "combat-icon"

var _source_size := Vector2i.ZERO
var _library_entries: Array[Dictionary] = []
var _selected_asset_id := ""
var _selection_callback := Callable()
var _focus_before_open: WeakRef


func _ready() -> void:
	(%LibraryEntries as ItemList).item_selected.connect(_select_library_entry)
	(%ChooseSource as Button).pressed.connect(_open_source_picker)
	(%SourceFiles as FileDialog).file_selected.connect(func(path: String) -> void: source_requested.emit(path))
	(%SourceFiles as FileDialog).canceled.connect(func() -> void: (%ChooseSource as Button).grab_focus())
	(%ArtKind as OptionButton).item_selected.connect(func(_index: int) -> void:
		_update_preview_size()
		_state_changed()
	)
	(%ArtMode as OptionButton).item_selected.connect(func(_index: int) -> void:
		_update_mode_help()
		_state_changed()
	)
	(%ArtFilter as OptionButton).item_selected.connect(func(_index: int) -> void: _state_changed())
	for control: SpinBox in [%CropX, %CropY, %CropSize]:
		control.value_changed.connect(func(_value: float) -> void: _crop_changed())
	(%ImportArt as Button).pressed.connect(_request_import)
	(%CancelArt as Button).pressed.connect(_dismiss)
	(%DoneArt as Button).pressed.connect(_dismiss)
	_apply_source_bounds()
	_update_preview_size()


func open_library(group_name: String = "", selection: Callable = Callable()) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_focus_before_open = weakref(focused) if focused != null else null
	(%GroupName as LineEdit).text = group_name
	_selection_callback = selection
	visible = true
	_fit()
	(%LibraryEntries as ItemList).grab_focus()
	opened.emit()
	_state_changed()


func bind_library(entries: Array[Dictionary]) -> void:
	_library_entries = entries.duplicate()
	_refresh_library()


func bind_source(filename: String, source_size: Vector2i) -> void:
	(%SourceName as Label).text = filename.get_file()
	_source_size = Vector2i(maxi(source_size.x, 0), maxi(source_size.y, 0))
	(%SourceDimensions as Label).text = "%d × %d" % [_source_size.x, _source_size.y] if _source_size.x > 0 and _source_size.y > 0 else "Source dimensions unavailable"
	_apply_source_bounds()
	_center_crop()
	_apply_source_bounds()
	_state_changed()


func bind_preview(texture: Texture2D, error: String = "") -> void:
	(%ImportArt as Button).disabled = texture == null
	(%NativePreview as TextureRect).texture = texture
	(%EnlargedPreview as TextureRect).texture = texture
	(%PreviewError as Label).text = error
	(%NativeSize as Label).text = "%d × %d native" % [texture.get_width(), texture.get_height()] if texture != null else "Native 1× result"


func finish_import(asset_id: String, kind: String) -> void:
	_selected_asset_id = asset_id
	artwork_selected.emit(asset_id, kind)
	_notify_selection(asset_id, kind)
	_refresh_library()
	(%LibraryEntries as ItemList).grab_focus()


func show_error(message: String) -> void:
	(%PreviewError as Label).text = message


func controller_focus_root() -> Node:
	return %SourceFiles if (%SourceFiles as FileDialog).visible else self


func dismiss() -> void:
	_dismiss()


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_update_preview_size()
	_fit.call_deferred()


func _open_source_picker() -> void:
	(%SourceFiles as FileDialog).popup_centered_ratio(0.88)
	(%SourceFiles as FileDialog).get_line_edit().grab_focus()


func _select_library_entry(index: int) -> void:
	var entry := _library_entries[index]
	var asset_id := str(entry.get("id", ""))
	var kind := str(entry.get("kind", PORTRAIT))
	artwork_selected.emit(asset_id, kind)
	_notify_selection(asset_id, kind)


func _refresh_library() -> void:
	var list := %LibraryEntries as ItemList
	list.clear()
	for entry: Dictionary in _library_entries:
		var label := str(entry.get("label", "Artwork"))
		var kind := str(entry.get("kind", PORTRAIT))
		var group := str(entry.get("group", ""))
		var index := list.item_count
		list.add_item("%s  ·  %s%s" % [label, "Portrait" if kind == PORTRAIT else "Combat icon", "  ·  " + group if not group.is_empty() else ""])
		list.set_item_metadata(index, str(entry.get("id", "")))
		list.set_item_tooltip(index, "%s · %s · %s" % [group, label, kind])
		var texture := entry.get("texture") as Texture2D
		if texture != null:
			list.set_item_icon(index, texture)
		if str(entry.get("id", "")) == _selected_asset_id:
			list.select(index)


func _request_import() -> void:
	import_requested.emit(
		(%GroupName as LineEdit).text.strip_edges(),
		(%ArtworkLabel as LineEdit).text.strip_edges(),
		_selected_kind(), _selected_mode(), _selected_filter(), _crop_rect()
	)


func _state_changed() -> void:
	if is_node_ready():
		(%EnlargedCaption as Label).text = "4× nearest preview"
		preview_requested.emit(_selected_kind(), _selected_mode(), _selected_filter(), _crop_rect())


func _selected_kind() -> String:
	return PORTRAIT if (%ArtKind as OptionButton).selected == 0 else COMBAT_ICON


func _selected_mode() -> String:
	return ["fit", "crop", "resize"][(%ArtMode as OptionButton).selected]


func _selected_filter() -> String:
	return "nearest" if (%ArtFilter as OptionButton).selected == 0 else "lanczos"


func _crop_rect() -> Rect2i:
	var size := int((%CropSize as SpinBox).value)
	return Rect2i(Vector2i(int((%CropX as SpinBox).value), int((%CropY as SpinBox).value)), Vector2i(size, size))


func _update_mode_help() -> void:
	var crop_mode := _selected_mode() == "crop"
	(%CropControls as HBoxContainer).visible = crop_mode
	(%CropHelp as Label).text = "Fit preserves proportions with transparent padding." if _selected_mode() == "fit" else "Crop selects one integer square from the source image." if crop_mode else "Resize maps the full image to a square and may distort it."


func _center_crop() -> void:
	if _source_size.x <= 0 or _source_size.y <= 0:
		return
	var side := mini(_source_size.x, _source_size.y)
	(%CropX as SpinBox).value = floori((_source_size.x - side) * 0.5)
	(%CropY as SpinBox).value = floori((_source_size.y - side) * 0.5)
	(%CropSize as SpinBox).value = side


func _apply_source_bounds() -> void:
	var available := _source_size.x > 0 and _source_size.y > 0
	(%CropSize as SpinBox).min_value = 1.0 if available else 0.0
	(%CropX as SpinBox).max_value = maxf(0.0, float(_source_size.x - 1))
	(%CropY as SpinBox).max_value = maxf(0.0, float(_source_size.y - 1))
	(%CropSize as SpinBox).max_value = maxf(0.0, float(mini(_source_size.x - int((%CropX as SpinBox).value), _source_size.y - int((%CropY as SpinBox).value))))
	for control: SpinBox in [%CropX, %CropY, %CropSize]:
		control.editable = available


func _crop_changed() -> void:
	if is_node_ready():
		_apply_source_bounds()
		_state_changed()


func _notify_selection(asset_id: String, kind: String) -> void:
	if _selection_callback.is_valid():
		_selection_callback.call(asset_id, kind)


func _update_preview_size() -> void:
	if not is_node_ready():
		return
	var side := 44 if _selected_kind() == PORTRAIT else 32
	(%NativePreview as TextureRect).custom_minimum_size = Vector2(side, side)
	(%EnlargedPreview as TextureRect).custom_minimum_size = Vector2(side * 4, side * 4)
	(%NativeSize as Label).text = "%d × %d native" % [side, side]


func _fit() -> void:
	if not is_node_ready():
		return
	var profile := UiSizing.profile_for(self)
	var area := profile.application_rect if profile != null else Rect2(Vector2.ZERO, size)
	var scale := profile.ui_scale if profile != null else 1.0
	var window := %ArtWindow as PanelContainer
	var compact := area.size.x < 1000.0 * scale
	(%ArtBody as BoxContainer).vertical = compact
	(%SettingsRow as GridContainer).columns = 2 if compact or profile != null and profile.font_scale > scale * 1.2 else 6
	var library := %LibraryPanel as PanelContainer
	library.custom_minimum_size = Vector2(0.0, 120.0) if compact else Vector2(235.0 * scale, 0.0)
	library.size_flags_vertical = Control.SIZE_FILL if compact else Control.SIZE_EXPAND_FILL
	window.size = Vector2(minf(1160.0 * scale, area.size.x * 0.96), minf(650.0 * scale, area.size.y * 0.94))
	window.position = area.position + (area.size - window.size) * 0.5


func _dismiss() -> void:
	if (%SourceFiles as FileDialog).visible:
		(%SourceFiles as FileDialog).hide()
		(%ChooseSource as Button).grab_focus()
		return
	hide()
	_selection_callback = Callable()
	var previous := _focus_before_open.get_ref() as Control if _focus_before_open != null else null
	_focus_before_open = null
	if previous != null and previous.is_visible_in_tree():
		previous.grab_focus()
	dismissed.emit()
