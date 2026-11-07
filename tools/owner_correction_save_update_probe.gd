## Exercises Trouble's owner-correction updates from one exact retained predecessor in new scratch storage.
## `terrain` starts from the archive before the terrain correction, `program` from the one before XAP 1794's.
extends "res://tools/marker_save_update_probe.gd"


## Adapts the chained policy to the probe's single-predecessor policy checks.
class BoundOwnerPolicy extends RefCounted:
	var last_error := ""
	var _update: OwnerCorrectionSaveUpdate
	var _old_hash: String

	func _init(update: OwnerCorrectionSaveUpdate, old_hash: String) -> void:
		_update = update
		_old_hash = old_hash

	func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
		return _update.eligible(campaign_id, old_hash, current_hash)

	func validate_archives(content: RealmzContent) -> bool:
		var valid := _update.validate_archives(content, _old_hash)
		last_error = _update.last_error
		return valid

	func updated_slot_id(source_slot: String, backup: bool, package_hash: String) -> String:
		return _update.updated_slot_id(source_slot, backup, package_hash)


var _start: Dictionary = {}


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or args[2] not in ["terrain", "program"] or not args[0].is_absolute_path() or not args[1].is_absolute_path() or DirAccess.dir_exists_absolute(args[1]) or FileAccess.file_exists(args[1]):
		printerr("Usage: -- <retained-original-directory> <new-absolute-scratch-directory> terrain|program")
		quit(2)
		return
	var records := OwnerCorrectionSaveUpdate.corrections()
	if records.is_empty() or DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		printerr("The pinned owner-correction receipts or scratch directory are unavailable.")
		quit(2)
		return
	_start = (records[-1] if args[2] == "terrain" else records[0]).previousPackage
	print("ISOLATED: pinned Trouble owner-correction save update from the %s predecessor; scratch packages/saves only" % args[2])
	_save_root = args[1].path_join("saves")
	var repository := PackageRepository.new()
	var app := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not _check(app.is_ok(), "application loads"):
		quit(1)
		return
	repository.set_application_content(app.content, app.media.assets())
	var current_hash: String = records[0].packageHash
	_check(not OwnerCorrectionSaveUpdate.new().eligible(str(records[0].campaignId), current_hash, current_hash), "current package is not its own predecessor")
	_check_campaign(repository, {"campaignId": records[0].campaignId, "file": records[0].file}, args[0], args[1])
	repository.close()
	var output := FileAccess.open(args[1].path_join("result.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"kind": "realmz.owner-correction-save-probe", "mode": args[2], "checks": _checks, "failures": _failures,
		"campaigns": _results, "proofMode": "isolated public save API; full write/readback"}, "\t"))
	output.close()
	print("OWNER_CORRECTION_SAVE_UPDATE mode=%s checks=%d failures=%d" % [args[2], _checks, _failures])
	call_deferred("quit", 0 if _failures == 0 and _results.size() == 1 else 1)


func _exercises_failures(_entry: Dictionary) -> bool:
	return true


## The marker probe already covers the shared paths; repeating them here reinstalls and revalidates the full archive.
func _exercises_shared_paths() -> bool:
	return false


func _previous(_entry: Dictionary) -> Dictionary:
	return _start


func _policy(installed_root: String, bundle_root: String = MarkerSaveUpdate.BUNDLE_ROOT) -> Variant:
	return BoundOwnerPolicy.new(OwnerCorrectionSaveUpdate.new(installed_root, bundle_root), str(_start.packageHash))


func _host(saves: SaveRepository, installed_root: String) -> SaveHostController:
	return SaveHostController.new(saves, null, null, null, null, null, null, CompleteRecordSaveUpdate.new(installed_root), OwnerCorrectionSaveUpdate.new(installed_root))
