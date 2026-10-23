## Runs explicit private corpus inputs through the owned import task, retaining packages before job cleanup.
extends "res://tools/verification_tree.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[2].is_absolute_path() or DirAccess.dir_exists_absolute(args[2]):
		printerr("Usage: scenario_import_task_probe.gd -- <importer-root> <source-inputs.json> <new-absolute-output-root>")
		quit(2)
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not value is Array:
		printerr("Source inputs must be an array.")
		quit(2)
		return
	var inputs: Array = value
	if inputs.is_empty() or DirAccess.make_dir_recursive_absolute(args[2]) != OK:
		printerr("Supply a nonempty source-input array and a new writable output root.")
		quit(2)
		return
	var results: Array[Dictionary] = []
	for index: int in inputs.size():
		var input: Dictionary = inputs[index]
		var task := ClassicScenarioImportTask.new()
		var started := Time.get_ticks_msec()
		task.start(str(input.sourceDirectory), args[2].path_join("jobs"), 20, args[0], str(input.get("startupFile", "")))
		while task.state == &"running" and Time.get_ticks_msec() - started < 600000:
			task.poll()
			await process_frame
		var row := _retain_result(task, input, args[2], index)
		row["milliseconds"] = Time.get_ticks_msec() - started
		results.append(row)
		task.close()
		print(JSON.stringify({"name": row.name, "event": row.event, "milliseconds": row.milliseconds}))
		var output := FileAccess.open(args[2].path_join("conversion-results.json"), FileAccess.WRITE)
		if output == null:
			printerr("Could not retain conversion evidence.")
			quit(1)
			return
		output.store_string(JSON.stringify(results, "\t"))
		output.close()
	quit()


func _retain_result(task: ClassicScenarioImportTask, input: Dictionary, root: String, index: int) -> Dictionary:
	var data: Dictionary = {}
	if not task.report_path.is_empty():
		var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(task.report_path))
		if report is Dictionary:
			data = report
	var event := "failed"
	if task.state == &"succeeded":
		var target := root.path_join("%03d.realmz2" % index)
		if DirAccess.copy_absolute(task.package_path, target) == OK and FileAccess.get_sha256(task.package_path) == FileAccess.get_sha256(target):
			event = "complete"
			data["packagePath"] = target
			data["archiveSha256"] = FileAccess.get_sha256(target)
		else:
			data["message"] = "Could not retain the converted archive."
	else:
		data["message"] = task.message
		data["code"] = str(task.error_code)
		data["startupCandidates"] = Array(task.startup_candidates)
	return {"name": str(input.name), "sourceDirectory": str(input.sourceDirectory), "event": event, "data": data}
