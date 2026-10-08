## Presents Classic item detail popover through the Godot interface.

class_name ClassicItemDetailPopover
extends CanvasLayer

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const TEXT := Color("e0e2e5")
const MUTED := Color("aeb6ba")

@export var detail_label_scene: PackedScene

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
	_panel = %ClassicItemDetailPanel
	_panel.theme = ui_theme
	_content = %ClassicItemDetailContent
	set_process(true)


func clear_hover() -> void:
	_hovered_source = null
	_hovered_detail = {}
	modifier_active = false


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
	var header := _content.get_node("ClassicItemDetailHeader") as HBoxContainer
	var fact_grid := _content.get_node("ClassicItemDetailFacts") as GridContainer
	var properties := _content.get_node("Properties") as VBoxContainer
	var restrictions := _content.get_node("Restrictions") as VBoxContainer
	for host: Node in [fact_grid, properties, restrictions]:
		for child: Node in host.get_children():
			host.remove_child(child)
			child.free()
	var icon := header.get_node("ClassicItemDetailIcon") as ClassicContentIcon
	icon.configure(String(_hovered_detail.get("iconResourceType", "cicn")), int(_hovered_detail.get("iconId", 0)), _media, 48.0, String(_hovered_detail.get("title", "Item")))
	%ClassicItemDetailTitle.text = String(_hovered_detail.get("title", "Item"))
	_bind_optional_text(%ClassicItemDetailSubtitle, String(_hovered_detail.get("subtitle", "")))
	_bind_optional_text(%ClassicItemDetailDescription, String(_hovered_detail.get("description", "")))
	var facts: Array = _hovered_detail.get("facts", [])
	fact_grid.visible = not facts.is_empty()
	for fact: Variant in facts:
		if fact is Dictionary:
			fact_grid.add_child(_label(String(fact.get("label", "")), GOLD))
			fact_grid.add_child(_label(String(fact.get("value", "")), TEXT))
	for line: Variant in _hovered_detail.get("properties", []):
		properties.add_child(_label(String(line), CYAN))
	for line: Variant in _hovered_detail.get("restrictions", []):
		restrictions.add_child(_label(String(line), MUTED))
	properties.visible = properties.get_child_count() > 0
	restrictions.visible = restrictions.get_child_count() > 0


func _bind_optional_text(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()


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


func _label(text: String, color: Color) -> Label:
	var label := detail_label_scene.instantiate() as Label
	label.text = text
	label.add_theme_color_override("font_color", color)
	return label
