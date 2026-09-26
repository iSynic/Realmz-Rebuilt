extends RefCounted


static func write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()


static func write_text(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)
		file.close()


static func write_package_record(root: String, filename: String, package_hash: String, campaign_id: String) -> PackageDiscoveryResult:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var path := root.path_join(filename)
	write_text(path, filename)
	return PackageDiscoveryResult.new(path, true, campaign_id, package_hash, "realmz-classic-1")


static func remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(absolute.path_join(name))
	for name: String in directory.get_directories():
		remove_tree(absolute.path_join(name))
	DirAccess.remove_absolute(absolute)
