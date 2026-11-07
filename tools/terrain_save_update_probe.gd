## Exercises Trouble's owner terrain update from its exact retained predecessor in new scratch storage.
extends "res://tools/marker_save_update_probe.gd"


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or DirAccess.dir_exists_absolute(args[1]) or FileAccess.file_exists(args[1]):
		printerr("Usage: -- <retained-original-directory> <new-absolute-scratch-directory>")
		quit(2)
		return
	var record := TerrainSaveUpdate.correction()
	if record.is_empty() or DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		printerr("The pinned terrain receipt or scratch directory is unavailable.")
		quit(2)
		return
	print("ISOLATED: pinned Trouble terrain save update; scratch packages/saves only")
	_save_root = args[1].path_join("saves")
	var repository := PackageRepository.new()
	var app := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not _check(app.is_ok(), "application loads"):
		quit(1)
		return
	repository.set_application_content(app.content, app.media.assets())
	var campaign_id: String = record.campaignId
	var current_hash: String = record.packageHash
	_check(not TerrainSaveUpdate.new().eligible(campaign_id, current_hash, current_hash), "current package is not its own predecessor")
	_check_campaign(repository, {"campaignId": record.campaignId, "file": record.file}, args[0], args[1])
	repository.close()
	var output := FileAccess.open(args[1].path_join("result.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"kind": "realmz.terrain-save-probe", "checks": _checks, "failures": _failures,
		"campaigns": _results, "proofMode": "isolated public save API; full write/readback"}, "\t"))
	output.close()
	print("TERRAIN_SAVE_UPDATE checks=%d failures=%d" % [_checks, _failures])
	call_deferred("quit", 0 if _failures == 0 and _results.size() == 1 else 1)


func _exercises_failures(_entry: Dictionary) -> bool:
	return true


## The marker probe already covers the shared paths; repeating them here reinstalls and revalidates the full archive.
func _exercises_shared_paths() -> bool:
	return false


func _previous(_entry: Dictionary) -> Dictionary:
	return TerrainSaveUpdate.correction().previousPackage


func _policy(installed_root: String, bundle_root: String = MarkerSaveUpdate.BUNDLE_ROOT) -> Variant:
	return TerrainSaveUpdate.new(installed_root, bundle_root)


func _host(saves: SaveRepository, installed_root: String) -> SaveHostController:
	return SaveHostController.new(saves, null, null, null, null, null, null, CompleteRecordSaveUpdate.new(installed_root), TerrainSaveUpdate.new(installed_root))
