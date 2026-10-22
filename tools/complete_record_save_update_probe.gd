## Reuses the historical full-envelope corpus against explicit complete-record pairs.
extends "res://tools/marker_save_update_probe.gd"

var _old_hash := ""


class BoundRecordPolicy extends RefCounted:
	var bound_hash: String
	var policy: CompleteRecordSaveUpdate
	var last_error: String:
		get: return policy.last_error

	func _init(installed: String, bundle: String, predecessor: String) -> void:
		policy = CompleteRecordSaveUpdate.new(installed, bundle)
		bound_hash = predecessor

	func validate_archives(content: RealmzContent) -> bool:
		return not policy.validate_archives(content, bound_hash).is_empty()

	func eligible(campaign: String, old_hash: String, current_hash: String) -> bool:
		return policy.eligible(campaign, old_hash, current_hash)

	func updated_slot_id(slot: String, backup: bool, current_hash: String) -> String:
		return policy.updated_slot_id(slot, backup, current_hash)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or DirAccess.dir_exists_absolute(args[1]):
		printerr("Expected explicit route manifest and new absolute scratch directory.")
		quit(2)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not manifest is Dictionary or manifest.get("kind") != "realmz.complete-records-save-probe-inputs":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	var repository := PackageRepository.new()
	var application := repository.load_package(ApplicationLibraryIdentity.PATH)
	if not _check(application.is_ok(), "pinned application loads"):
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	for route: Dictionary in manifest.routes:
		_old_hash = route.packageHash
		var correction := CompleteRecordPackageDelta.correction(route.campaignId, route.currentPackageHash)
		var previous := CompleteRecordPackageDelta.previous(correction, _old_hash)
		if not _check(not previous.is_empty() and previous.archiveSha256 == route.archiveSha256, "route has an exact runtime receipt"):
			continue
		var scratch: String = args[1].path_join(route.campaignId + "-" + _old_hash.left(8))
		DirAccess.make_dir_recursive_absolute(scratch)
		_save_root = scratch.path_join("saves")
		var entry := {"campaignId": route.campaignId, "file": correction.file,
			"packageHash": route.currentPackageHash, "previous": previous}
		_check_campaign(repository, entry, String(route.path).get_base_dir(), scratch)
		if not _results.is_empty():
			_results[-1]["route"] = route.route
			_results[-1]["sourceArchiveSha256"] = FileAccess.get_sha256(route.path)
	repository.close()
	var output := FileAccess.open(args[1].path_join("result.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"kind": "realmz.complete-records-save-probe", "checks": _checks,
		"failures": _failures, "campaigns": _results, "proofMode": "isolated public save API; full write/readback"}, "\t"))
	output.close()
	print("COMPLETE_RECORD_SAVE_UPDATE checks=%d failures=%d" % [_checks, _failures])
	call_deferred("quit", 0 if _failures == 0 and _results.size() == manifest.routes.size() else 1)


func _previous(entry: Dictionary) -> Dictionary:
	return entry.previous


func _policy(installed_root: String, bundle_root: String = MarkerSaveUpdate.BUNDLE_ROOT) -> Variant:
	return BoundRecordPolicy.new(installed_root, bundle_root, _old_hash)


func _host(saves: SaveRepository, installed_root: String) -> SaveHostController:
	return SaveHostController.new(saves, null, null, null, null, null, null, CompleteRecordSaveUpdate.new(installed_root))


func _check_corrected_archive_failure(current: RealmzContent, installed_root: String, scratch: String) -> void:
	var entry := CompleteRecordPackageDelta.correction(current.campaign_id, current.package_hash)
	var bad_bundle := scratch.path_join("rejected-bundle")
	DirAccess.make_dir_recursive_absolute(bad_bundle)
	var bytes := FileAccess.get_file_as_bytes(MarkerSaveUpdate.BUNDLE_ROOT.path_join(entry.file))
	_write_bytes(bad_bundle.path_join(entry.file), bytes + PackedByteArray([0]))
	_check(not _policy(installed_root, bad_bundle).validate_archives(current), "altered corrected archive rejects")
