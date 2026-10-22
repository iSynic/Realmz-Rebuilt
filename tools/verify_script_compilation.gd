## Compiles every project GDScript so warnings promoted to errors in project settings fail the gate.
## Editor import only compiles scripts it needs, so coordinators and tools would otherwise escape.
extends SceneTree


func _initialize() -> void:
	var pending: Array[String] = ["res://src", "res://tests", "res://tools"]
	var compiled := 0
	while not pending.is_empty():
		var directory: String = pending.pop_back()
		for child: String in DirAccess.get_directories_at(directory):
			pending.append(directory.path_join(child))
		for file: String in DirAccess.get_files_at(directory):
			# Reloading the running probe itself would deadlock, so it is skipped.
			if file.ends_with(".gd") and directory.path_join(file) != get_script().resource_path:
				ResourceLoader.load(directory.path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE)
				compiled += 1
	print("Compiled %d project scripts." % compiled)
	quit()
