class_name ClassicRouteScreen
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
		action.visible = route_id not in [&"exploration", &"combat", &"vault", &"inventory"]
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
	if find_child("WorkspaceFooter", true, false) != null:
		return
	var footer := Control.new()
	footer.name = "WorkspaceFooter"
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer)
	action.owner = null
	action.reparent(footer)
	action.owner = self
	action.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var navigation_size := Vector2(82.0, 34.0)
	action.offset_left = -navigation_size.x - 8.0
	action.offset_top = -navigation_size.y - 8.0
	action.offset_right = -8.0
	action.offset_bottom = -8.0
	if route_id == &"spells":
		var context_actions := HBoxContainer.new()
		context_actions.name = "WorkspaceContextActions"
		context_actions.add_theme_constant_override("separation", 5)
		context_actions.anchor_left = 0.0
		context_actions.anchor_top = 1.0
		context_actions.anchor_right = 1.0
		context_actions.anchor_bottom = 1.0
		context_actions.offset_left = 8.0
		context_actions.offset_top = -navigation_size.y - 8.0
		context_actions.offset_right = -navigation_size.x - 14.0
		context_actions.offset_bottom = -8.0
		footer.add_child(context_actions)
	var body_scroll := scroll
	if body_scroll == null:
		body_scroll = get_node("WorkspaceColumn/BodyClip/ScreenBodyScroll") as ScrollContainer
	body_scroll.offset_bottom = -navigation_size.y - 16.0


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
