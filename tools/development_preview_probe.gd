## Exercises one isolated Providence preview request through public package/session boundaries.

extends SceneTree

var _request: DevelopmentPreviewRequest


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/development_preview_probe.gd -- <preview-request.json>")
		call_deferred("_quit_cleanly", 2)
		return
	_request = DevelopmentPreviewRequest.decode(_read_json(arguments[0]))
	if _request == null:
		printerr("PREVIEW_REQUEST_REJECTED invalid_request: The preview request is malformed or unsupported.")
		call_deferred("_quit_cleanly", 1)
		return
	var preview := DevelopmentPreviewSession.new()
	if not preview.load_request(_request):
		_finish(preview.failure_fields(), 1)
		return
	var session := GameSession.new()
	if not preview.start(session):
		_finish(preview.failure_fields(), 1)
		return
	_finish(preview.ready_fields(), 0)


func _finish(fields: Dictionary, exit_code: int) -> void:
	var write_error := DevelopmentPreviewResultWriter.write(_request, fields)
	if not write_error.is_empty():
		printerr("PREVIEW_RESULT_REJECTED write_failed: %s" % write_error)
		call_deferred("_quit_cleanly", 1)
		return
	call_deferred("_quit_cleanly", exit_code)


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
