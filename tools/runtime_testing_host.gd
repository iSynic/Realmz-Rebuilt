## Launches a visibly identified fixture with scratch persistence before composition.
extends Control


func _enter_tree() -> void:
	var arguments := OS.get_cmdline_user_args()
	var request: RuntimeTestingFixtureRequest
	if arguments.size() == 1 and OS.is_debug_build():
		var file := FileAccess.open(arguments[0], FileAccess.READ)
		if file != null and file.get_length() <= 65536:
			request = RuntimeTestingFixtureRequest.decode(JSON.parse_string(file.get_as_text()))
			file.close()
	if request == null:
		printerr("FIXTURE_REQUEST_REJECTED: A valid isolated launch request is required.")
		get_tree().quit.call_deferred(2)
		var rejected_application := get_node("RealmzApplication")
		remove_child(rejected_application)
		rejected_application.free()
		return
	var application := get_node("RealmzApplication") as RealmzApplication
	application.set_meta(&"runtime_testing_fixture", request)
	application.set_meta(&"startup_splash_suppressed", true)
	application.set_meta(&"startup_front_door_revealed", true)
	DisplayServer.window_set_title("Realmz Rebuilt — TEST FIXTURE %s" % request.fixture_id.left(8))
