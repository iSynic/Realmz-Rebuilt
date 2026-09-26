## Records independent installation and session-initialization outcomes for a private import corpus.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("Usage: scenario_import_probe.gd -- <conversion-results.json> <scratch-install-root> <report.json>")
		quit(2)
		return
	var inputs: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not inputs is Array or not args[1].is_absolute_path() or args[1].begins_with(OS.get_user_data_dir()):
		printerr("Supply a conversion result array and an absolute scratch root outside player storage.")
		quit(2)
		return
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		printerr(application.error_message)
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var rows: Array[Dictionary] = []
	var failures := 0
	for item: Dictionary in inputs:
		var row := {"name": item.get("name", ""), "conversion": item.get("event", "unknown"), "installation": "not-run", "sessionInitialization": "not-run", "exercisedGameplay": "not-run", "campaignCompletion": "not-run"}
		if item.get("event") == "complete":
			var converted: Dictionary = item.get("data", {})
			var installed := repository.install_package(String(converted.get("packagePath", "")), args[1])
			row["packageHash"] = converted.get("packageHash", "")
			row["installation"] = "passed" if installed.is_ok() else "failed"
			if installed.is_ok():
				row["installedPath"] = installed.installed_path
				var session := GameSession.new()
				var step := session.start(installed.package.content, 1)
				row["sessionInitialization"] = "failed" if step.state == SessionStep.State.FAILED else "passed"
				if step.state == SessionStep.State.FAILED:
					row["startupError"] = {"code": step.error_code, "message": step.error_message}
				else:
					session.close()
			else:
				failures += 1
				row["installationError"] = {"code": installed.error_code, "message": installed.error_message}
		else:
			row["conversionError"] = item.get("data", {}).get("message", "")
		rows.append(row)
		print(JSON.stringify(row))
		await process_frame
	repository.close()
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	if output == null:
		printerr("Cannot save corpus report: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	output.store_string(JSON.stringify({"formatVersion": 1, "scenarios": rows}, "\t"))
	output.close()
	quit(1 if failures > 0 else 0)
