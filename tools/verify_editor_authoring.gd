@tool
## Exercises real EditorInterface saves, then production binding of the saved scenes.
extends SceneTree

const REGISTRY := "res://addons/realmz_builder/scene_previews.json"
const RECEIPT := "res://.godot/realmz_editor_authoring_cycles.json"
const PLUGIN := preload("res://addons/realmz_builder/realmz_builder_plugin.gd")
const FIXTURES := preload("res://addons/realmz_builder/realmz_builder_preview_fixtures.gd")
const TINT := Color(0.85, 0.9, 1.0)

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.has("--editor-cycle") and Engine.is_editor_hint():
		await _editor_cycles()
	elif arguments.has("--runtime-cycle") and not Engine.is_editor_hint():
		await _runtime_cycles()
	else:
		_failures.append("Pass --editor-cycle to --editor or --runtime-cycle to the ordinary runtime.")
	for failure: String in _failures:
		printerr("AUTHORING_FAILURE: ", failure)
	quit(0 if _failures.is_empty() else 1)


func _editor_cycles() -> void:
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	var contracts: Dictionary = registry["sceneContracts"]
	var plugin := PLUGIN.new()
	plugin.call("_load_registry")
	var registrations: Dictionary = plugin.get("_registrations")
	var receipt: Array[Dictionary] = []
	var only_id := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			only_id = argument.trim_prefix("--only=")
	for registration: Dictionary in registry["scenes"]:
		var surface_id := str(registration["id"])
		if not only_id.is_empty() and surface_id != only_id:
			continue
		var scene := load("res://" + str(registration["scene"])) as PackedScene
		var copy := scene.instantiate() as Control
		var packed := PackedScene.new()
		if packed.pack(copy) != OK:
			_failures.append("%s did not pack for the editor" % surface_id)
			copy.free()
			continue
		copy.free()
		var path := "res://.godot/realmz_authoring_%s.tscn" % surface_id
		if ResourceSaver.save(packed, path) != OK:
			_failures.append("%s did not save a disposable editor copy" % surface_id)
			continue
		registrations[path.trim_prefix("res://")] = registration
		plugin.set("_registrations", registrations)
		EditorInterface.open_scene_from_path(path)
		var edited := await _wait_for_editor_scene(path)
		if edited == null or edited.scene_file_path != path:
			_failures.append("%s did not open in EditorInterface; edited=%s, open=%s" % [surface_id, edited.scene_file_path if edited != null else "null", EditorInterface.get_open_scenes()])
			continue
		plugin.set("_edited_root", edited)
		plugin.call("_apply_preview", "Wide")
		var contract: Dictionary = contracts[surface_id]
		var edit_node := str(contract.get("authoringEditNode", ""))
		var raw_nodes: Array = contract["rawSceneNodes"]
		var target := edited.get_node_or_null(NodePath(edit_node)) as Control if not edit_node.is_empty() else _authored_control(edited, raw_nodes)
		if target == null:
			_failures.append("%s has no editable authored control" % surface_id)
			plugin.call("_apply_changes")
			continue
		var node_path := edited.get_path_to(target)
		var width := target.custom_minimum_size.x + 2.0
		target.custom_minimum_size.x = width
		target.modulate = TINT
		plugin.call("_apply_changes")
		EditorInterface.save_scene_as(path, false)
		var edited_id := edited.get_instance_id()
		EditorInterface.close_scene()
		EditorInterface.open_scene_from_path(path)
		var reopened := await _wait_for_editor_scene(path, edited_id, node_path)
		var retained := reopened.get_node_or_null(node_path) as Control if reopened != null else null
		if retained == null or not is_equal_approx(retained.custom_minimum_size.x, width) or retained.modulate != TINT:
			_failures.append("%s lost the child edit after editor reload: %s width=%s color=%s, expected=%s" % [surface_id, node_path, retained.custom_minimum_size.x if retained != null else "missing", retained.modulate if retained != null else "missing", width])
		if surface_id == "party-assembly" and reopened != null and (reopened.find_child("StoredCharacterList", true, false) as Container).get_child_count() != 0:
			_failures.append("Party Setup saved sample Character Files rows")
		if surface_id == "application-shell" and reopened != null:
			if reopened.theme != null:
				_failures.append("Game Shell saved a temporary preview theme")
			var portrait_button := reopened.get_node("PartyRoster/RosterColumn/PartyScroll/PartyList/Position1/Member/Character") as Button
			if portrait_button.icon != null:
				_failures.append("Game Shell saved a sample portrait")
		receipt.append({"id": surface_id, "path": path, "child": String(node_path), "width": width})
	EditorInterface.close_scene()
	await process_frame
	plugin.free()
	var file := FileAccess.open(RECEIPT, FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt))
	file.close()
	print("EDITOR_CYCLES=", receipt.size(), " FAILURES=", _failures.size())


func _runtime_cycles() -> void:
	var receipt: Array = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
	for entry: Dictionary in receipt:
		var scene := load(str(entry["path"])) as PackedScene
		if scene == null:
			_failures.append("%s saved scene cannot load in runtime" % entry["id"])
			continue
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		viewport.disable_3d = true
		root.add_child(viewport)
		var surface := scene.instantiate() as Control
		viewport.add_child(surface)
		var retained := surface.get_node_or_null(NodePath(str(entry["child"]))) as Control
		var expected_width: float = entry["width"]
		if retained == null or not is_equal_approx(retained.custom_minimum_size.x, expected_width) or retained.modulate != TINT:
			_failures.append("%s lost its child edit on runtime entry" % entry["id"])
		if not FIXTURES.bind(surface, str(entry["id"]), "Wide"):
			_failures.append("%s did not bind in production" % entry["id"])
		elif retained == null or not is_equal_approx(retained.custom_minimum_size.x, expected_width) or retained.modulate != TINT:
			_failures.append("%s replaced its authored layout or appearance during production binding" % entry["id"])
		viewport.queue_free()
		await process_frame
		DirAccess.remove_absolute(ProjectSettings.globalize_path(str(entry["path"])))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECEIPT))
	print("RUNTIME_CYCLES=", receipt.size(), " FAILURES=", _failures.size())


func _authored_control(surface: Control, patterns: Array) -> Control:
	for pattern: String in patterns:
		var candidates := surface.find_children(pattern, "Control", true, false)
		if not candidates.is_empty():
			for candidate: Node in candidates:
				if candidate is Control:
					return candidate as Control
	return null


func _wait_for_editor_scene(path: String, prior_id: int = 0, required_node: NodePath = NodePath()) -> Control:
	for frame: int in 120:
		await process_frame
		var edited := EditorInterface.get_edited_scene_root() as Control
		if edited != null and edited.scene_file_path == path and (prior_id == 0 or edited.get_instance_id() != prior_id) and (required_node.is_empty() or edited.get_node_or_null(required_node) != null):
			return edited
	return null
