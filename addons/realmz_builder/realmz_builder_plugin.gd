@tool
extends EditorPlugin

const REGISTRY_PATH := "res://addons/realmz_builder/scene_previews.json"
const DOCK_SCENE := preload("res://addons/realmz_builder/realmz_builder_dock.tscn")
const AUTHORING_SAMPLES := preload("res://addons/realmz_builder/realmz_builder_authoring_samples.gd")
const SAMPLE_PATH := "res://addons/realmz_builder/editor_samples.json.gz"

var _dock: Control
var _profiles: Array = []
var _registrations: Dictionary = {}
var _sample_records: Dictionary = {}
var _edited_root: Node
var _samples: RefCounted
var _active_profile := "Wide"
var _show_samples := true


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
	scene_saved.connect(_on_scene_saved)
	_on_scene_changed(get_editor_interface().get_edited_scene_root())


func _exit_tree() -> void:
	_clear_preview()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock = null


func _load_registry() -> void:
	_profiles = []
	_registrations = {}
	_sample_records = {}
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
		var path := String(registration.get("scene", ""))
		if not _registrations.has(path) or String(registration.get("id", "")) == "party-assembly":
			_registrations[path] = registration
	var samples_file := FileAccess.open_compressed(SAMPLE_PATH, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if samples_file == null:
		push_error("Realmz Builder could not open %s" % SAMPLE_PATH)
		return
	var parsed_samples: Variant = JSON.parse_string(samples_file.get_as_text())
	if parsed_samples is Dictionary:
		_sample_records = parsed_samples
	else:
		push_error("Realmz Builder editor samples are invalid.")


func _on_scene_changed(scene_root: Node) -> void:
	_clear_preview()
	_edited_root = scene_root
	if _dock == null:
		return
	if typeof(_registrations) != TYPE_DICTIONARY:
		_load_registry()
	var scene_path := _resource_relative_path(scene_root.scene_file_path) if scene_root != null else ""
	_dock.present_registration(Dictionary(_registrations.get(scene_path, {})))
	_active_profile = "Wide"
	_show_samples = true
	_apply_preview(_active_profile)


func _apply_preview(profile: String) -> void:
	_clear_preview()
	if not is_instance_valid(_edited_root):
		return
	if typeof(_registrations) != TYPE_DICTIONARY or typeof(_sample_records) != TYPE_DICTIONARY:
		_load_registry()
	var scene_path := _resource_relative_path(_edited_root.scene_file_path)
	var registration := Dictionary(_registrations.get(scene_path, {}))
	if registration.is_empty():
		return
	var surface_id := String(registration.get("id", ""))
	var fixture_profile := profile
	if surface_id == "party-assembly" and profile == "Character creation":
		surface_id = "character-creation"
		fixture_profile = "Wide"
	_active_profile = profile
	_show_samples = true
	var sample_key := "%s/%s" % [surface_id, fixture_profile]
	if _sample_records.has(sample_key):
		_samples = AUTHORING_SAMPLES.new()
		_samples.populate_snapshot(_edited_root, Array(_sample_records[sample_key]))


func _clear_preview() -> void:
	_show_samples = false
	if _samples != null:
		_samples.clear()
		_samples = null


func _apply_changes() -> void:
	if _samples != null:
		_samples.clear()
		_samples = null


func _on_scene_saved(path: String) -> void:
	if _show_samples and is_instance_valid(_edited_root) and _edited_root.scene_file_path == path:
		_apply_preview(_active_profile)


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
