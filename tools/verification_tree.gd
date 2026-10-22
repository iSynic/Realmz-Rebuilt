## Gives verification processes disposable user storage before scenes are constructed.
extends SceneTree


func _init() -> void:
	var directory := "RealmzVerification/run-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", directory)
	var absolute_root := OS.get_user_data_dir()
	if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
		push_error("Cannot create isolated verification storage: " + absolute_root)
		quit(1)
	print("Verification user storage: " + absolute_root)


func _initialize() -> void:
	# Used directly by the aggregate's real main-scene smoke launch.
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_error("Cannot load the configured main scene for verification.")
		quit(1)
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	current_scene = instance
