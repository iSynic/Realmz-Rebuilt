## Presents Classic item detail popover through the Godot interface.

class_name ClassicItemDetailPopover
extends CanvasLayer

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const TEXT := Color("e0e2e5")
const MUTED := Color("aeb6ba")
const ITEM_DETAIL_HEADER_SCENE_PATH := "res://src/ui/inventory/classic_item_detail_header.tscn"

@export var detail_label_scene: PackedScene
@export var fact_grid_scene: PackedScene

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
	var header := (load(ITEM_DETAIL_HEADER_SCENE_PATH) as PackedScene).instantiate() as HBoxContainer
	_content.add_child(header)
	var icon := header.get_node("ClassicItemDetailIcon") as ClassicContentIcon
	icon.configure(String(_hovered_detail.get("iconResourceType", "cicn")), int(_hovered_detail.get("iconId", 0)), _media, 48.0, String(_hovered_detail.get("title", "Item")))
	var identity := header.get_node("Identity") as VBoxContainer
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
		var fact_grid := fact_grid_scene.instantiate() as GridContainer
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
	var label := detail_label_scene.instantiate() as Label
	label.text = text
	label.add_theme_color_override("font_color", color)
	if not variation.is_empty():
		label.theme_type_variation = variation
	return label
