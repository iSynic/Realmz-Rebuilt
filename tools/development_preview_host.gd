## Launches the export-excluded interactive Providence preview scene.

extends Control


func _enter_tree() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		_reject("Usage: godot --path <project> --scene res://tools/development_preview_host.tscn -- <preview-request.json>")
		return
	var request := DevelopmentPreviewRequest.decode(_read_json(arguments[0]))
	if request == null:
		_reject("PREVIEW_REQUEST_REJECTED invalid_request: The preview request is malformed or unsupported.")
		return
	var application := get_node("RealmzApplication") as RealmzApplication
	application.set_meta(&"development_preview_request", request)
	application.set_meta(&"startup_splash_suppressed", true)
	application.set_meta(&"startup_front_door_revealed", true)
	DisplayServer.window_set_title("Realmz Rebuilt — Providence Preview")


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed


func _reject(message: String) -> void:
	printerr(message)
	get_tree().quit.call_deferred(2)
