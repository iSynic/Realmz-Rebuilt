## Castle's independent indoor party marker: five pages of 24 original icons.
class_name IndoorPartyIconPicker
extends VBoxContainer

signal icon_selected(index: int)

const PAGE_SIZE := 24

var _media: ClassicMediaCatalog
var _selected := PresentationSettings.DEFAULT_INDOOR_PARTY_ICON
var _page := PresentationSettings.DEFAULT_INDOOR_PARTY_ICON / PAGE_SIZE
var _buttons: Array[Button] = []


func _ready() -> void:
	var template := get_node("IconTemplate") as Button
	for slot: int in PAGE_SIZE:
		var button := template.duplicate() as Button
		button.name = "Icon%d" % slot
		button.visible = true
		button.pressed.connect(_choose_slot.bind(slot))
		get_node("Choices/Grid").add_child(button)
		_buttons.append(button)
	(get_node("Summary/Change") as Button).pressed.connect(_open)
	(get_node("Choices/Actions/Previous") as Button).pressed.connect(_change_page.bind(-1))
	(get_node("Choices/Actions/Next") as Button).pressed.connect(_change_page.bind(1))
	(get_node("Choices/Actions/Default") as Button).pressed.connect(_restore_default)
	(get_node("Choices/Actions/Done") as Button).pressed.connect(_close)
	visibility_changed.connect(_on_visibility_changed)


func bind_selection(index: int, media: ClassicMediaCatalog) -> void:
	_selected = index
	_media = media
	(get_node("Summary/Current") as Button).icon = _texture(index)
	(get_node("Summary/Current") as Button).text = "Icon %d%s" % [index + 1, " · Classic default" if index == PresentationSettings.DEFAULT_INDOOR_PARTY_ICON else ""]
	(get_node("Summary/Change") as Button).disabled = media == null
	_refresh_page()


func _texture(index: int) -> Texture2D:
	return _media.image_texture(_media.asset_by_resource("cicn", 9000 + index)) if _media != null else null


func _open() -> void:
	_page = _selected / PAGE_SIZE
	get_node("Choices").show()
	_refresh_page()
	_focus_selection.call_deferred()


func _focus_selection() -> void:
	if not is_visible_in_tree() or not get_node("Choices").visible:
		return
	_buttons[_selected % PAGE_SIZE].grab_focus()
	var parent := get_parent()
	while parent != null:
		if parent is ScrollContainer:
			(parent as ScrollContainer).ensure_control_visible(_buttons[_selected % PAGE_SIZE])
			break
		parent = parent.get_parent()


func _close() -> void:
	get_node("Choices").hide()
	(get_node("Summary/Change") as Button).grab_focus()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		get_node("Choices").hide()


func _change_page(delta: int) -> void:
	_page = wrapi(_page + delta, 0, PresentationSettings.INDOOR_PARTY_ICON_COUNT / PAGE_SIZE)
	_refresh_page()


func _refresh_page() -> void:
	for slot: int in _buttons.size():
		var index := _page * PAGE_SIZE + slot
		var button := _buttons[slot]
		button.icon = _texture(index)
		button.disabled = button.icon == null
		button.set_pressed_no_signal(index == _selected)
		button.tooltip_text = "Indoor party icon %d" % (index + 1)
		button.set_meta("record_id", "indoor-icon-%d" % index)
	(get_node("Choices/Actions/Page") as Label).text = "%d / 5" % (_page + 1)


func _choose_slot(slot: int) -> void:
	_selected = _page * PAGE_SIZE + slot
	bind_selection(_selected, _media)
	icon_selected.emit(_selected)


func _restore_default() -> void:
	_page = PresentationSettings.DEFAULT_INDOOR_PARTY_ICON / PAGE_SIZE
	_choose_slot(PresentationSettings.DEFAULT_INDOOR_PARTY_ICON % PAGE_SIZE)
