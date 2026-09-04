@tool
extends EditorPlugin

const REGISTRY_PATH := "res://addons/realmz_builder/scene_previews.json"
const DOCK_SCENE := preload("res://addons/realmz_builder/realmz_builder_dock.tscn")
const PREVIEW_FIXTURES := preload("res://addons/realmz_builder/realmz_builder_preview_fixtures.gd")
const PREVIEW_NODE_NAME := "__RealmzBuilderPreview"

var _dock: Control
var _profiles: Array = []
var _registrations: Dictionary = {}
var _edited_root: Node


func _enter_tree() -> void:
	_load_registry()
	if DisplayServer.get_name() == "headless":
		return
	_dock = DOCK_SCENE.instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	_dock.configure(_profiles)
	_dock.profile_requested.connect(_apply_preview)
	_dock.clear_requested.connect(_clear_preview)
	_dock.path_requested.connect(_open_path)
	scene_changed.connect(_on_scene_changed)
	_on_scene_changed(get_editor_interface().get_edited_scene_root())


func _exit_tree() -> void:
	_clear_preview()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null


func _load_registry() -> void:
	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		push_error("Realmz Builder could not open %s" % REGISTRY_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Realmz Builder preview registry is invalid JSON.")
		return
	_profiles = Array(parsed.get("profiles", []))
	for value: Variant in Array(parsed.get("scenes", [])):
		var registration := Dictionary(value)
		_registrations[String(registration.get("scene", ""))] = registration


func _on_scene_changed(scene_root: Node) -> void:
	_clear_preview()
	_edited_root = scene_root
	if _dock == null:
		return
	var scene_path := _resource_relative_path(scene_root.scene_file_path) if scene_root != null else ""
	_dock.present_registration(Dictionary(_registrations.get(scene_path, {})))


func _apply_preview(profile: String) -> void:
	_clear_preview()
	if _edited_root == null:
		return
	var scene_path := _resource_relative_path(_edited_root.scene_file_path)
	var registration := Dictionary(_registrations.get(scene_path, {}))
	if registration.is_empty():
		return
	var preview_root := Control.new()
	preview_root.name = PREVIEW_NODE_NAME
	preview_root.set_meta("editor_only", true)
	preview_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_edited_root.add_child(preview_root)
	preview_root.owner = null
	var scene_resource := load("res://" + scene_path) as PackedScene
	var preview_surface := scene_resource.instantiate() as Control if scene_resource != null else null
	var preview_bound := false
	if preview_surface != null:
		preview_root.add_child(preview_surface)
		preview_surface.owner = null
		preview_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview_bound = PREVIEW_FIXTURES.bind(preview_surface, String(registration.get("id", "")), profile)
		if not preview_bound:
			preview_surface.queue_free()
	var badge := Label.new()
	badge.name = "PreviewProfile"
	badge.text = "Realmz Builder · %s · %s%s" % [String(registration.get("id", "scene")), profile, "" if preview_bound else " · representative data pending"]
	badge.position = Vector2(12.0, 12.0)
	badge.z_index = 4096
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_root.add_child(badge)
	badge.owner = null
	if not preview_bound and _edited_root.has_method("apply_editor_preview"):
		_edited_root.call("apply_editor_preview", profile)


func _clear_preview() -> void:
	if _edited_root == null:
		return
	var preview := _edited_root.get_node_or_null(PREVIEW_NODE_NAME)
	if preview != null:
		_edited_root.remove_child(preview)
		preview.queue_free()
	if _edited_root.has_method("clear_editor_preview"):
		_edited_root.call("clear_editor_preview")


func _open_path(path: String) -> void:
	var resource_path := "res://" + path.trim_prefix("res://")
	if path.get_extension() in ["gd", "tscn", "tres"]:
		var resource := load(resource_path)
		if resource != null:
			get_editor_interface().edit_resource(resource)
			return
	OS.shell_open(ProjectSettings.globalize_path(resource_path))


func _resource_relative_path(path: String) -> String:
	return path.trim_prefix("res://").replace("\\", "/")
