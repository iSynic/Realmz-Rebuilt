## Owns staged and cancellable execution of the native scenario importer.

class_name ClassicScenarioImportTask
extends RefCounted

class ProcessDriver extends RefCounted:
	func start_process(executable: String, arguments: PackedStringArray) -> int:
		return OS.create_process(executable, arguments, false)

	func is_process_running(process_id: int) -> bool:
		return OS.is_process_running(process_id)

	func kill_process(process_id: int) -> Error:
		return OS.kill(process_id)

var state: StringName = &"idle"
var phase: StringName = &""
var message: String = ""
var source_directory: String = ""
var package_path: String = ""
var warning_count: int = 0
var diagnostic_details: Array[String] = []
var startup_candidates: Array[String] = []
var report_path: String = ""
var _pid: int = -1
var _job_root: String = ""
var _event_offset: int = 0
var _completed: bool = false
var _preparation: Thread
var _executable: String = ""
var _process_driver: ProcessDriver = ProcessDriver.new()
var _startup_file: String = ""


func _init(process_driver: ProcessDriver = null) -> void:
	if process_driver != null:
		_process_driver = process_driver


func start(directory: String, job_parent: String, importer_root: String = "", startup_file: String = "") -> bool:
	if state == &"running" or _pid > 0 or _preparation != null or not _job_root.is_empty():
		return false
	if not startup_file.is_empty() and (startup_file.get_file() != startup_file or startup_file.contains("/") or startup_file.contains("\\") or startup_file in [".", ".."]):
		return _fail("The selected scenario startup file must be a filename inside the selected folder.")
	source_directory = directory
	_startup_file = startup_file
	package_path = ""
	warning_count = 0
	diagnostic_details.clear()
	startup_candidates.clear()
	report_path = ""
	_completed = false
	_event_offset = 0
	state = &"running"
	phase = &"checking_files"
	message = "Checking files…"
	var root := importer_root
	if root.is_empty():
		root = ProjectSettings.globalize_path("res://importer") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("importer")
	var executable := root.path_join("providence-native-adapter" + (".exe" if OS.get_name() == "Windows" else ""))
	if not FileAccess.file_exists(executable):
		return _fail("The scenario importer is missing from this Rebuilt installation.")
	if DirAccess.make_dir_recursive_absolute(job_parent) != OK:
		return _fail("Could not create scenario import storage.")
	_job_root = job_parent.path_join("job-%s" % Crypto.new().generate_random_bytes(12).hex_encode())
	if DirAccess.make_dir_absolute(_job_root) != OK:
		return _fail("Could not create the scenario import job.")
	var owner_file := FileAccess.open(_job_root.path_join("owner.json"), FileAccess.WRITE)
	if owner_file == null:
		return _fail("Could not record scenario import ownership.")
	owner_file.store_string(JSON.stringify({"formatVersion": 1, "processId": OS.get_process_id()}))
	owner_file.close()
	_executable = executable
	_preparation = Thread.new()
	if _preparation.start(_prepare_job.bind(root, directory)) != OK:
		_preparation = null
		return _fail("Could not prepare scenario import storage.")
	return true


func _prepare_job(root: String, directory: String) -> String:
	var verification := _verify_bundle(root)
	if not verification.is_empty():
		return verification
	var application_path := _job_root.path_join("application.realmz2")
	var application := FileAccess.open(application_path, FileAccess.WRITE)
	if application == null:
		return "Could not prepare the application library for import."
	application.store_buffer(FileAccess.get_file_as_bytes(ApplicationLibraryIdentity.PATH))
	application.flush()
	var write_error := application.get_error()
	application.close()
	if write_error != OK:
		return "Could not write the application library for import (error %d)." % write_error
	var request := {"formatVersion": 1, "sourceDirectory": directory, "outputDirectory": _job_root.path_join("conversion"), "supportDirectory": root.path_join("support"), "applicationPackage": application_path, "applicationLibraryIdentity": {"campaignId": ApplicationLibraryIdentity.CAMPAIGN_ID, "packageHash": ApplicationLibraryIdentity.PACKAGE_HASH}}
	if not _startup_file.is_empty():
		request["startupFile"] = _startup_file
	var request_path := _job_root.path_join("request.json")
	var file := FileAccess.open(request_path, FileAccess.WRITE)
	if file == null:
		return "Could not write the scenario import request."
	file.store_string(JSON.stringify(request))
	file.close()
	return ""


func poll() -> void:
	if state != &"running" and state != &"cancelled" and not (state == &"failed" and _pid > 0):
		return
	if _preparation != null:
		if _preparation.is_alive():
			return
		var preparation_error: String = _preparation.wait_to_finish()
		_preparation = null
		if state == &"cancelled":
			_remove_owned_job()
			return
		if not preparation_error.is_empty():
			_fail(preparation_error)
			return
		_pid = _process_driver.start_process(_executable, PackedStringArray(["import-rebuilt-scenario", _job_root.path_join("request.json")]))
		if _pid <= 0:
			_fail("Could not start the scenario importer.")
			return
		var owner_file := FileAccess.open(_job_root.path_join("owner.json"), FileAccess.WRITE)
		if owner_file != null:
			owner_file.store_string(JSON.stringify({"formatVersion": 1, "processId": OS.get_process_id(), "converterId": _pid}))
			owner_file.close()
	if state == &"cancelled":
		if _pid > 0 and _process_driver.is_process_running(_pid):
			return
		_pid = -1
		_remove_owned_job()
		return
	_read_events()
	if _pid > 0 and _process_driver.is_process_running(_pid):
		return
	_pid = -1
	_read_events()
	if state == &"running":
		state = &"succeeded" if _completed else &"failed"
		if not _completed:
			message = "The scenario importer stopped before completing. Retry the import."


func cancel() -> void:
	if state != &"running":
		return
	state = &"cancelled"
	message = "Scenario import cancelled."
	if _pid > 0 and _process_driver.is_process_running(_pid):
		_process_driver.kill_process(_pid)


func close() -> void:
	if state == &"running" or _pid > 0:
		if state == &"running":
			cancel()
		elif _pid > 0 and _process_driver.is_process_running(_pid):
			_process_driver.kill_process(_pid)
	if _preparation != null:
		_preparation.wait_to_finish()
		_preparation = null
	# A killed child may still hold files briefly. Keep its owner record for startup recovery.
	if _pid > 0 and _process_driver.is_process_running(_pid):
		return
	_pid = -1
	_remove_owned_job()


func _remove_owned_job() -> void:
	# Only paths generated by this task are eligible for removal.
	if not _job_root.is_empty() and _job_root.get_file().begins_with("job-"):
		_remove_job(_job_root)
	_job_root = ""


func _read_events() -> void:
	var path := _job_root.path_join("conversion/events.jsonl")
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	file.seek(_event_offset)
	while file.get_position() < file.get_length():
		var line := file.get_line()
		var next_offset := file.get_position()
		file.seek(next_offset - 1)
		var complete_line := file.get_8() == 10
		file.seek(next_offset)
		if not complete_line:
			break
		var parsed: Variant = _parse_json(line)
		_event_offset = next_offset
		if not parsed is Dictionary:
			continue
		var event: Dictionary = parsed
		if event.get("formatVersion") != 1 or not event.get("data") is Dictionary:
			continue
		var data: Dictionary = event.data
		match str(event.get("event", "")):
			"startup_selection":
				startup_candidates.clear()
				for candidate: Variant in data.get("candidates", []):
					var basename := str(candidate)
					if not basename.is_empty() and basename not in [".", ".."] and basename.get_file() == basename and not basename.contains("\\") and not startup_candidates.has(basename):
						startup_candidates.append(basename)
			"diagnostics":
				_retain_diagnostics(data)
			"progress":
				phase = StringName(str(data.get("phase", "")))
				message = str(data.get("message", "Importing scenario…"))
			"failed":
				state = &"failed"
				message = str(data.get("message", "Scenario import failed."))
			"complete":
				_retain_diagnostics(data)
				package_path = str(data.get("packagePath", ""))
				warning_count = int(data.get("warningCount", 0))
				for detail: Variant in data.get("warnings", []):
					if not diagnostic_details.has(str(detail)):
						diagnostic_details.append(str(detail))
				_completed = not package_path.is_empty() and FileAccess.file_exists(package_path)
	file.close()


func _retain_diagnostics(report: Dictionary) -> void:
	var merged_report := report.duplicate(true)
	if not report_path.is_empty() and FileAccess.file_exists(report_path):
		var previous: Variant = _parse_json(FileAccess.get_file_as_string(report_path))
		if previous is Dictionary:
			merged_report = previous.duplicate(true)
			merged_report.merge(report, true)
	if not merged_report.has("formatVersion"):
		merged_report["formatVersion"] = 1
	if not merged_report.has("sourceName"):
		merged_report["sourceName"] = source_directory.get_file()
	for instruction: Variant in merged_report.get("unsupportedInstructions", []):
		if instruction is Dictionary:
			var detail := str(instruction.get("message", "Unsupported instruction"))
			if not diagnostic_details.has(detail):
				diagnostic_details.append(detail)
	var reports := _job_root.get_base_dir().get_base_dir().path_join("import-reports")
	if DirAccess.make_dir_recursive_absolute(reports) != OK:
		diagnostic_details.append("Could not retain the import diagnostic report.")
		return
	report_path = reports.path_join(_job_root.get_file() + ".json")
	var output := FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		diagnostic_details.append("Could not write the import diagnostic report.")
		return
	output.store_string(JSON.stringify(merged_report, "\t"))
	output.flush()
	output.close()


func _fail(detail: String) -> bool:
	state = &"failed"
	message = detail
	return false


func _remove_job(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in DirAccess.get_directories_at(path):
		if not directory.is_link(name):
			_remove_job(path.path_join(name))
	DirAccess.remove_absolute(path)


func recover_abandoned_jobs(parent: String) -> void:
	var directory := DirAccess.open(parent)
	if directory == null:
		return
	for name: String in directory.get_directories():
		if not name.begins_with("job-") or directory.is_link(name):
			continue
		var path := parent.path_join(name)
		var owner: Variant = _parse_json(FileAccess.get_file_as_string(path.path_join("owner.json")))
		if owner is Dictionary and owner.get("formatVersion") == 1 and not OS.is_process_running(int(owner.get("processId", -1))) and not OS.is_process_running(int(owner.get("converterId", -1))):
			_remove_job(path)


func _verify_bundle(root: String) -> String:
	var manifest: Variant = _parse_json(FileAccess.get_file_as_string(root.path_join("build-manifest.json")))
	if not manifest is Dictionary or manifest.get("formatVersion") != 1 or not manifest.get("executable") is Dictionary or not manifest.get("supportFiles") is Array:
		return "The scenario importer build manifest is missing or invalid. Reinstall Rebuilt."
	var executable: Dictionary = manifest.executable
	if str(executable.get("path", "")) != _executable.get_file() or FileAccess.get_sha256(_executable) != str(executable.get("sha256", "")):
		return "The scenario importer executable failed its integrity check. Reinstall Rebuilt."
	for value: Variant in manifest.supportFiles:
		if not value is Dictionary:
			return "The scenario importer support manifest is invalid."
		var relative := str(value.get("path", ""))
		if relative.is_empty() or relative.is_absolute_path() or ".." in relative.split("/") or relative.contains("\\"):
			return "The scenario importer support manifest contains an unsafe path."
		var path := root.path_join("support").path_join(relative)
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(value.get("sha256", "")):
			return "Scenario importer support failed its integrity check: %s" % relative
	return ""


func _parse_json(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data
