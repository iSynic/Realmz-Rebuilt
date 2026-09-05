## Owns screen frame presentation behavior for its scene-authored screen.

class_name ScreenFrame
extends PanelContainer

signal back_requested

@export var route_id: StringName
@export var title: String = "Realmz"
@export_multiline var description: String = ""

@onready var scroll: ScrollContainer = %ScreenBodyScroll
@onready var body: VBoxContainer = %ScreenBody
@onready var _title_label: Label = %ScreenTitle
@onready var _description_label: Label = %ScreenDescription
@onready var _header: BoxContainer = %WorkspaceHeader
@onready var _back_action: Button = %RouteBackAction
@onready var _header_rule: HSeparator = $WorkspaceColumn/HeaderRule


func _ready() -> void:
	_title_label.text = title
	_description_label.text = description
	_description_label.max_lines_visible = 2
	_description_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_description_label.visible = not description.is_empty()
	_configure_navigation()
	_update_back_visibility()
	apply_route_chrome()


func set_workspace_rect(workspace_rect: Rect2) -> void:
	var inset := Vector2.ZERO if route_id == &"spells" else Vector2(8.0, 8.0)
	position = workspace_rect.position + inset
	size = workspace_rect.size - inset * 2.0
	if _header != null:
		_header.vertical = workspace_rect.size.x < 900.0
	_configure_navigation()
	_update_back_visibility()
	apply_route_chrome()


func _update_back_visibility() -> void:
	var action := _back_action
	if action == null:
		action = get_node_or_null("WorkspaceColumn/WorkspaceHeader/RouteBackAction") as Button
	if action != null:
		action.visible = route_id not in [&"exploration", &"combat", &"vault", &"inventory", &"services"]
		if not action.pressed.is_connected(_emit_back_requested):
			action.pressed.connect(_emit_back_requested)


func _configure_navigation() -> void:
	var action := _back_action
	if action == null:
		action = get_node_or_null("WorkspaceColumn/WorkspaceHeader/RouteBackAction") as Button
	if action == null:
		return
	action.text = "Back"
	if route_id != &"spells":
		return
	var footer := find_child("WorkspaceFooter", true, false) as Control
	var back_host := find_child("SpellsBackHost", true, false) as Container
	assert(footer != null and back_host != null, "The Spells route requires its authored footer and Back host")
	if action.get_parent() != back_host:
		action.owner = null
		action.reparent(back_host)
		action.owner = self
	var navigation_size := Vector2(82.0, 34.0)
	action.custom_minimum_size = navigation_size
	action.size_flags_horizontal = Control.SIZE_SHRINK_END


func apply_route_chrome() -> void:
	var show_route_heading := route_id != &"spells"
	var route_title := get_node_or_null("WorkspaceColumn/WorkspaceHeader/ScreenTitle") as Label
	var route_description := get_node_or_null("WorkspaceColumn/WorkspaceHeader/ScreenDescription") as Label
	var route_rule := get_node_or_null("WorkspaceColumn/HeaderRule") as HSeparator
	if route_title != null:
		route_title.visible = show_route_heading
	if route_description != null:
		route_description.visible = show_route_heading and not description.is_empty()
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
