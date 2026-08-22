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


func _ready() -> void:
	_title_label.text = title
	_description_label.text = description
	_description_label.max_lines_visible = 2
	_description_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_description_label.visible = not description.is_empty()
	_update_back_visibility()


func set_workspace_rect(workspace_rect: Rect2) -> void:
	var inset := Vector2.ZERO if route_id == &"spells" else Vector2(8.0, 8.0)
	position = workspace_rect.position + inset
	size = workspace_rect.size - inset * 2.0
	if _header != null:
		_header.vertical = workspace_rect.size.x < 900.0
	_update_back_visibility()


func _update_back_visibility() -> void:
	var action := _back_action
	if action == null:
		action = get_node_or_null("WorkspaceColumn/WorkspaceHeader/RouteBackAction") as Button
	if action != null:
		action.visible = route_id not in [&"exploration", &"combat", &"vault"]
		if not action.pressed.is_connected(_emit_back_requested):
			action.pressed.connect(_emit_back_requested)


func _emit_back_requested() -> void:
	back_requested.emit()


func scroll_control() -> ScrollContainer:
	return scroll if scroll != null else get_node("WorkspaceColumn/ScreenBodyScroll") as ScrollContainer


func body_control() -> VBoxContainer:
	return body if body != null else get_node("WorkspaceColumn/ScreenBodyScroll/ScreenBody") as VBoxContainer
