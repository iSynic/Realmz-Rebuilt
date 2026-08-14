class_name ClassicRouteScreen
extends PanelContainer

@export var route_id: StringName
@export var title: String = "Realmz"
@export_multiline var description: String = ""

@onready var scroll: ScrollContainer = %ScreenBodyScroll
@onready var body: VBoxContainer = %ScreenBody
@onready var _title_label: Label = %ScreenTitle
@onready var _description_label: Label = %ScreenDescription
@onready var _header: BoxContainer = %WorkspaceHeader


func _ready() -> void:
	_title_label.text = title
	_description_label.text = description
	_description_label.visible = not description.is_empty()


func set_workspace_rect(workspace_rect: Rect2) -> void:
	position = workspace_rect.position + Vector2(8.0, 8.0)
	size = workspace_rect.size - Vector2(16.0, 16.0)
	if _header != null:
		_header.vertical = workspace_rect.size.x < 620.0
