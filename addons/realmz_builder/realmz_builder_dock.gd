@tool
extends VBoxContainer

signal profile_requested(profile: String)
signal clear_requested
signal path_requested(path: String)

@onready var _scene_name: Label = %SceneName
@onready var _status: Label = %PreviewStatus
@onready var _profile: OptionButton = %Profile
@onready var _apply: Button = %ApplyPreview
@onready var _clear: Button = %ClearPreview
@onready var _guide: Button = %Guide
@onready var _controller: Button = %Controller
@onready var _view: Button = %View
@onready var _tests: Button = %Tests
@onready var _authoring_scene: Button = %AuthoringScene

var _registration: Dictionary = {}


func _ready() -> void:
	_apply.pressed.connect(func() -> void: profile_requested.emit(_profile.get_item_text(_profile.selected)))
	_clear.pressed.connect(func() -> void: clear_requested.emit())
	_guide.pressed.connect(func() -> void: _request_link("guide"))
	_controller.pressed.connect(func() -> void: _request_link("controller"))
	_view.pressed.connect(func() -> void: _request_link("view"))
	_tests.pressed.connect(_request_first_test)
	if _authoring_scene != null:
		_authoring_scene.pressed.connect(func() -> void: _request_link("authoringScene"))


func configure(profiles: Array) -> void:
	_profile.clear()
	for profile: Variant in profiles:
		_profile.add_item(String(profile))


func present_registration(registration: Dictionary) -> void:
	_registration = registration
	var registered := not registration.is_empty()
	configure(["Wide", "Compact", "Empty", "Long Content", "Unavailable", "Error"])
	if String(registration.get("id", "")) == "party-assembly":
		_profile.add_item("Character creation")
	_scene_name.text = String(registration.get("id", "Unregistered scene")).capitalize()
	var production_binding := bool(registration.get("productionBinding", false))
	_status.text = "Editable production scene with representative data" if production_binding else "Editable layout; representative data pending"
	_profile.disabled = not registered
	_apply.disabled = not registered
	_clear.disabled = not registered
	_guide.disabled = not registered
	_controller.disabled = not registered
	_view.disabled = not registered
	_tests.disabled = not registered or Array(registration.get("tests", [])).is_empty()
	if _authoring_scene != null:
		_authoring_scene.visible = registered and registration.has("authoringScene")


func _request_link(key: String) -> void:
	var path := String(_registration.get(key, ""))
	if not path.is_empty():
		path_requested.emit(path)


func _request_first_test() -> void:
	var tests := Array(_registration.get("tests", []))
	if not tests.is_empty():
		path_requested.emit(String(tests[0]))
