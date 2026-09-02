class_name ClassicItemDetailPopover
extends CanvasLayer

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const TEXT := Color("e0e2e5")
const MUTED := Color("aeb6ba")
const CONTENT_ICON_SCRIPT := preload("res://src/presentation/classic_content_icon.gd")

var modifier_active := false:
	set(value):
		modifier_active = value
		_refresh_visibility()
var _media: ClassicMediaCatalog
var _hovered_source: Control
var _hovered_detail: Dictionary = {}
var _panel: PanelContainer
var _content: VBoxContainer


func configure(media: ClassicMediaCatalog, ui_theme: Theme = null) -> void:
	_media = media
	name = "ClassicItemDetailPopover"
	layer = 90
	_panel = PanelContainer.new()
	_panel.name = "ClassicItemDetailPanel"
	_panel.theme_type_variation = &"ClassicTextWell"
	_panel.theme = ui_theme
	_panel.custom_minimum_size = Vector2(360.0, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_content = VBoxContainer.new()
	_content.name = "ClassicItemDetailContent"
	_content.add_theme_constant_override("separation", 4)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)
	set_process(true)


func bind_hover(source: Control, detail: Dictionary) -> void:
	if source == null:
		return
	source.mouse_entered.connect(_hover_started.bind(source, detail.duplicate(true)))
	source.mouse_exited.connect(_hover_ended.bind(source))


func _process(_delta: float) -> void:
	var alt_pressed := Input.is_key_pressed(KEY_ALT)
	if modifier_active != alt_pressed:
		modifier_active = alt_pressed
	if _panel != null and _panel.visible:
		_place_panel()


func _hover_started(source: Control, detail: Dictionary) -> void:
	_hovered_source = source
	_hovered_detail = detail
	_refresh_visibility()


func _hover_ended(source: Control) -> void:
	if _hovered_source != source:
		return
	_hovered_source = null
	_hovered_detail = {}
	_refresh_visibility()


func _refresh_visibility() -> void:
	if _panel == null:
		return
	var should_show := modifier_active and is_instance_valid(_hovered_source) and not _hovered_detail.is_empty()
	if not should_show:
		_panel.visible = false
		return
	_render_detail()
	_panel.visible = true
	_panel.reset_size()
	call_deferred("_place_panel")


func _render_detail() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.free()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(header)
	var icon := CONTENT_ICON_SCRIPT.new() as Control
	icon.name = "ClassicItemDetailIcon"
	icon.configure(String(_hovered_detail.get("iconResourceType", "cicn")), int(_hovered_detail.get("iconId", 0)), _media, 48.0, String(_hovered_detail.get("title", "Item")))
	header.add_child(icon)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(identity)
	var title := _label(String(_hovered_detail.get("title", "Item")), GOLD, &"ClassicHeading")
	title.name = "ClassicItemDetailTitle"
	identity.add_child(title)
	var subtitle := String(_hovered_detail.get("subtitle", ""))
	if not subtitle.is_empty():
		identity.add_child(_label(subtitle, CYAN))
	var description := String(_hovered_detail.get("description", ""))
	if not description.is_empty():
		var description_label := _label(description, TEXT)
		description_label.name = "ClassicItemDetailDescription"
		_content.add_child(description_label)
	var facts: Array = _hovered_detail.get("facts", [])
	if not facts.is_empty():
		var fact_grid := GridContainer.new()
		fact_grid.name = "ClassicItemDetailFacts"
		fact_grid.columns = 2
		fact_grid.add_theme_constant_override("h_separation", 12)
		fact_grid.add_theme_constant_override("v_separation", 2)
		fact_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(fact_grid)
		for fact: Variant in facts:
			if fact is Dictionary:
				fact_grid.add_child(_label(String(fact.get("label", "")), GOLD))
				fact_grid.add_child(_label(String(fact.get("value", "")), TEXT))
	for line: Variant in _hovered_detail.get("properties", []):
		_content.add_child(_label(String(line), CYAN))
	for line: Variant in _hovered_detail.get("restrictions", []):
		_content.add_child(_label(String(line), MUTED))


func _place_panel() -> void:
	if _panel == null or not _panel.visible:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	var desired := viewport.get_mouse_position() + Vector2(18.0, 18.0)
	var panel_size := _panel.get_combined_minimum_size()
	_panel.position = Vector2(clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - panel_size.x - 8.0)), clampf(desired.y, 8.0, maxf(8.0, viewport_size.y - panel_size.y - 8.0)))


func _label(text: String, color: Color, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not variation.is_empty():
		label.theme_type_variation = variation
	return label
