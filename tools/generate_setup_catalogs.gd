extends "res://tools/verification_tree.gd"

const BUNDLED_DIRECTORY := "res://src/storage/packages/bundled_campaigns"
const SETUP_CACHE_SCRIPT := preload("res://src/storage/packages/package_setup_cache.gd")
const REPOSITORY_SCRIPT := preload("res://src/storage/packages/package_repository.gd")
const ARCHIVE_READER_SCRIPT := preload("res://src/storage/packages/package_archive_reader.gd")
const APPLICATION_IDENTITY_SCRIPT := preload("res://src/storage/packages/application_library_identity.gd")
const USAGE := "Usage: godot --headless --path <project> --script res://tools/generate_setup_catalogs.gd [--check]"


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 1 or arguments.size() == 1 and arguments[0] != "--check":
		_fail(USAGE, 2)
		return
	var check_only := arguments.size() == 1
	var archive_root := ProjectSettings.globalize_path(BUNDLED_DIRECTORY)
	var archives: Array[String] = []
	for file_name: String in DirAccess.get_files_at(archive_root):
		if file_name.ends_with(".realmz2"): archives.append(file_name)
	archives.sort()
	if archives.size() != 13:
		_fail("Expected 13 bundled scenario archives in %s; found %d." % [archive_root, archives.size()], 1)
		return
	var scratch_root := "user://setup-catalog-generation-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var scratch_absolute := ProjectSettings.globalize_path(scratch_root)
	if DirAccess.dir_exists_absolute(scratch_absolute):
		_fail("Scratch directory already exists; refusing to reuse it: %s" % scratch_absolute, 1)
		return
	if DirAccess.make_dir_recursive_absolute(scratch_absolute) != OK:
		_fail("Could not create isolated setup-catalog scratch directory: %s" % scratch_absolute, 1)
		return
	var repository := REPOSITORY_SCRIPT.new()
	var application := repository.load_bundled_package(APPLICATION_IDENTITY_SCRIPT.PATH, APPLICATION_IDENTITY_SCRIPT.CAMPAIGN_ID, APPLICATION_IDENTITY_SCRIPT.PACKAGE_HASH)
	if not application.is_ok():
		_cleanup_scratch(scratch_absolute)
		_fail("Pinned application library failed validation: %s" % application.error_message, 1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var failures: Array[String] = []
	for archive_name: String in archives:
		var archive_path := archive_root.path_join(archive_name)
		var failure := _process_archive(repository, archive_path, scratch_root, check_only)
		if not failure.is_empty():
			failures.append("%s: %s" % [archive_name, failure])
	repository.close()
	var cleanup_error := _cleanup_scratch(scratch_absolute)
	if not cleanup_error.is_empty():
		failures.append("scratch cleanup: %s" % cleanup_error)
	if not failures.is_empty():
		for failure: String in failures:
			printerr("SETUP_CATALOG_REJECTED %s" % failure)
		call_deferred("_quit_cleanly", 1)
		return
	print("SETUP_CATALOGS_%s count=%d application=%s" % ["CHECKED" if check_only else "WRITTEN", archives.size(), APPLICATION_IDENTITY_SCRIPT.PACKAGE_HASH])
	call_deferred("_quit_cleanly", 0)


func _process_archive(repository: PackageRepository, archive_path: String, scratch_root: String, check_only: bool) -> String:
	var prepared: PackageSetupResult = repository.prepare_setup(archive_path, scratch_root)
	if not prepared.is_ok():
		return "setup documents could not be derived: %s" % prepared.error_message
	var archive := ZIPReader.new()
	if archive.open(archive_path) != OK:
		return "archive could not be reopened to bind cache identity"
	var archive_reader := ARCHIVE_READER_SCRIPT.new()
	var manifest_value: Variant = archive_reader.read_document(archive, "manifest.json")
	archive.close()
	if not manifest_value is Dictionary:
		return "manifest could not be decoded for cache identity"
	var manifest: Dictionary = manifest_value
	var archive_hash: String = archive_reader.sha256_file(archive_path)
	var derived_path := ProjectSettings.globalize_path(scratch_root).path_join("%s.json" % String(manifest.get("packageHash", "")))
	var documents: Dictionary = SETUP_CACHE_SCRIPT.read(derived_path, archive_hash, manifest, APPLICATION_IDENTITY_SCRIPT.PACKAGE_HASH)
	if documents.is_empty():
		return "freshly derived setup cache is missing or failed identity/payload validation"
	var expected_path := ProjectSettings.globalize_path(scratch_root).path_join("expected-%s.setup.json" % String(manifest.get("packageHash", "")))
	if not SETUP_CACHE_SCRIPT.write(expected_path, archive_hash, manifest, APPLICATION_IDENTITY_SCRIPT.PACKAGE_HASH, documents):
		return "could not serialize deterministic setup cache"
	var expected_bytes := FileAccess.get_file_as_bytes(expected_path)
	if expected_bytes.is_empty():
		return "deterministic setup cache serialization produced no bytes"
	var sidecar_path := archive_path + ".setup.json"
	if check_only:
		if not FileAccess.file_exists(sidecar_path):
			return "setup cache is missing; run tools/generate_setup_catalogs.gd to generate it"
		var existing_bytes := FileAccess.get_file_as_bytes(sidecar_path)
		var existing_documents: Dictionary = SETUP_CACHE_SCRIPT.read(sidecar_path, archive_hash, manifest, APPLICATION_IDENTITY_SCRIPT.PACKAGE_HASH)
		if existing_documents.is_empty() or existing_documents != documents or existing_bytes != expected_bytes:
			return "setup cache identity or payload is stale; run tools/generate_setup_catalogs.gd to regenerate it"
		return ""
	var output := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if output == null:
		return "could not write setup cache at %s" % sidecar_path
	output.store_buffer(expected_bytes)
	output.flush()
	output.close()
	var written_documents: Dictionary = SETUP_CACHE_SCRIPT.read(sidecar_path, archive_hash, manifest, APPLICATION_IDENTITY_SCRIPT.PACKAGE_HASH)
	if written_documents.is_empty() or written_documents != documents:
		return "written setup cache failed identity/payload readback"
	return ""


func _cleanup_scratch(scratch_absolute: String) -> String:
	var entries := DirAccess.get_files_at(scratch_absolute)
	for entry: String in entries:
		var path := scratch_absolute.path_join(entry)
		if DirAccess.remove_absolute(path) != OK:
			return "could not remove generated scratch file %s" % path
	if DirAccess.remove_absolute(scratch_absolute) != OK:
		return "could not remove isolated scratch directory %s" % scratch_absolute
	return ""


func _fail(message: String, code: int) -> void:
	printerr("SETUP_CATALOG_REJECTED %s" % message)
	call_deferred("_quit_cleanly", code)


func _quit_cleanly(code: int) -> void:
	quit(code)
