## Owns screen frame presentation behavior for its scene-authored screen.

class_name ScreenFrame
extends PanelContainer

signal back_requested

@export var route_id: StringName
@export var compact_spells_back_width := 60.0

@onready var scroll: ScrollContainer = %ScreenBodyScroll
@onready var body: VBoxContainer = %ScreenBody
@onready var _title_label: Label = %ScreenTitle
@onready var _description_label: Label = %ScreenDescription
@onready var _header: BoxContainer = %WorkspaceHeader
@onready var _back_action: Button = %RouteBackAction
@onready var _header_rule: HSeparator = $WorkspaceColumn/HeaderRule
var _compact_route_exit := false
var _compact_spell_route := false
var _spells_back_authored_min_size := Vector2.ZERO


func _ready() -> void:
	_description_label.max_lines_visible = 2
	_description_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_description_label.visible = not _description_label.text.is_empty()
	_configure_navigation()
	_update_back_visibility()
	apply_route_chrome()


func set_workspace_rect(workspace_rect: Rect2) -> void:
	var inset := Vector2.ZERO if route_id == &"spells" else Vector2(8.0, 8.0)
	position = workspace_rect.position + inset
	size = workspace_rect.size - inset * 2.0
	var profile := UiSizing.profile_for(self)
	var logical_width := workspace_rect.size.x / (profile.ui_scale if profile != null else 1.0)
	_compact_route_exit = (logical_width < 900.0 or (profile != null and profile.id == UiLayoutProfile.COMPACT)) and route_id in [&"inventory", &"services"]
	_compact_spell_route = logical_width < 320.0 and route_id == &"spells"
	if _header != null:
		_header.vertical = logical_width < 900.0 and not _compact_route_exit
	_configure_navigation()
	_update_back_visibility()
	apply_route_chrome()


func _update_back_visibility() -> void:
	var action := _back_action
	if action == null:
		action = get_node_or_null("WorkspaceColumn/WorkspaceHeader/RouteBackAction") as Button
	if action != null:
		action.visible = _compact_route_exit or route_id not in [&"exploration", &"combat", &"vault", &"inventory", &"services"]
		if not action.pressed.is_connected(_emit_back_requested):
			action.pressed.connect(_emit_back_requested)


func _configure_navigation() -> void:
	var action := find_child("SpellsBackAction", true, false) as Button if route_id == &"spells" else _back_action
	if action == null:
		action = get_node_or_null("WorkspaceColumn/WorkspaceHeader/RouteBackAction") as Button
	if action == null:
		return
	_back_action = action
	if route_id != &"spells":
		return
	assert(action.name == &"SpellsBackAction", "The Spells route requires its authored footer Back action")
	if _spells_back_authored_min_size == Vector2.ZERO:
		_spells_back_authored_min_size = action.custom_minimum_size
	var navigation_size := _spells_back_authored_min_size
	if _compact_spell_route:
		navigation_size.x = compact_spells_back_width
	action.custom_minimum_size = navigation_size


func apply_route_chrome() -> void:
	var show_route_heading := route_id != &"spells"
	var route_title := get_node_or_null("WorkspaceColumn/WorkspaceHeader/ScreenTitle") as Label
	var route_description := get_node_or_null("WorkspaceColumn/WorkspaceHeader/ScreenDescription") as Label
	var route_rule := get_node_or_null("WorkspaceColumn/HeaderRule") as HSeparator
	if route_title != null:
		route_title.visible = show_route_heading
	if route_description != null:
		route_description.visible = show_route_heading and not route_description.text.is_empty()
	if route_rule != null:
		route_rule.visible = show_route_heading


func _emit_back_requested() -> void:
	back_requested.emit()


func scroll_control() -> ScrollContainer:
	return scroll if scroll != null else get_node("WorkspaceColumn/BodyClip/ScreenBodyScroll") as ScrollContainer


func body_control() -> VBoxContainer:
	return body if body != null else get_node("WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody") as VBoxContainer


func context_action_control() -> Container:
	return find_child("WorkspaceContextActions", true, false) as Container
