## Admits the thirteen pinned stock native-marker corrections.
class_name MarkerSaveUpdate
extends RefCounted

const BUNDLE_ROOT := "res://src/storage/packages/bundled_campaigns"
const CATALOG_PATH := BUNDLE_ROOT + "/castle-bundled-scenarios.provenance.json"
const RECEIPT_PATH := BUNDLE_ROOT + "/native-map-triggers.json"
const RECEIPT_SHA256 := "da7567117db3154e02c68ab01f890b715546823265835f116db162581a5b1443"
const DOCUMENTS: Array[String] = ["content.json", "world.json", "scenario.json", "assets/index.json"]

var last_error := ""
var _installed_root: String
var _bundle_root: String
var _transitions: Dictionary = {}
var _catalog_loaded := false


func _init(installed_root: String = "user://packages", bundle_root: String = BUNDLE_ROOT) -> void:
	_installed_root = installed_root
	_bundle_root = bundle_root


func transition(campaign_id: String, current_hash: String) -> Dictionary:
	_load_catalog()
	var entry: Dictionary = _transitions.get(campaign_id, {})
	return entry.duplicate(true) if entry.get("packageHash") == current_hash else {}


func eligible(campaign_id: String, old_hash: String, current_hash: String) -> bool:
	var entry := transition(campaign_id, current_hash)
	return not entry.is_empty() and entry.previousPackage.packageHash == old_hash


func updated_slot_id(source_slot: String, backup: bool, current_hash: String) -> String:
	var suffix := "%s-markers-%s" % ["-backup" if backup else "", current_hash.left(8)]
	return source_slot.left(128 - suffix.length()) + suffix


func validate_archives(content: RealmzContent) -> bool:
	last_error = ""
	var entry := transition(content.campaign_id, content.package_hash) if content != null else {}
	if entry.is_empty():
		return _fail("This campaign revision has no verified marker update.")
	var previous: Dictionary = entry.previousPackage
	var old_path := _installed_root.path_join(content.campaign_id).path_join("%s.realmz2" % previous.packageHash)
	var new_path := _bundle_root.path_join(entry.file)
	if not FileAccess.file_exists(old_path):
		return _fail("The original campaign package is missing. Restore its retained installation before updating this save.")
	if FileAccess.get_sha256(old_path) != previous.archiveSha256 or FileAccess.get_sha256(new_path) != entry.archiveSha256:
		return _fail("The original or corrected campaign archive does not match the approved marker update.")
	var installation_error := SaveUpdateInstallation.validate(old_path, content.campaign_id, previous.packageHash, previous.archiveSha256)
	if not installation_error.is_empty():
		return _fail(installation_error)
	var old_files := _read_archive(old_path)
	var new_files := _read_archive(new_path)
	if not CompressionPackageDelta.reverse_manifest(new_files, content.campaign_id, content.package_hash):
		return _fail("The source-compression revision differs from its approved delta.")
	var program := ProgramPackageDelta.correction(content.campaign_id, content.package_hash)
	if not program.is_empty() and not ProgramPackageDelta.reverse_payloads(new_files, program):
		return _fail("The subsequent native source retention differs from its approved delta.")
	if old_files.is_empty() or old_files.keys() != new_files.keys():
		return _fail("The marker update changed the package inventory.")
	for path: String in old_files:
		if path != "manifest.json" and path not in DOCUMENTS and old_files[path] != new_files[path]:
			return _fail("The marker update changed an unrelated payload: %s." % path)
	return _validate_documents(old_files, new_files, entry.correction) or _fail("The package documents differ beyond the approved native-marker correction.")


func _load_catalog() -> void:
	if _catalog_loaded:
		return
	_catalog_loaded = true
	if FileAccess.get_sha256(RECEIPT_PATH) != RECEIPT_SHA256:
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECEIPT_PATH))
	if not catalog is Dictionary or not report is Dictionary or catalog.get("acceptedApplicationLibrary", {}).get("packageHash") != ApplicationLibraryIdentity.PACKAGE_HASH:
		return
	if catalog.get("scenarios", []).size() != 13 or report.get("scenarios", []).size() != 13:
		return
	var transitions: Dictionary = {}
	for entry: Dictionary in catalog.scenarios:
		var refresh: Dictionary = entry.get("nativeTileRefresh", {})
		var previous: Dictionary = refresh.get("previousPackage", {})
		var rows: Array = report.scenarios.filter(func(row: Dictionary) -> bool: return row.outputFile == entry.file)
		if rows.size() != 1 or entry.get("campaignId") != String(entry.file).trim_suffix(".realmz2") or transitions.has(entry.campaignId):
			return
		var row: Dictionary = rows[0]
		var marker_identity: Dictionary = entry
		var compression := CompressionPackageDelta.correction(entry.campaignId, entry.packageHash)
		if entry.has("sourceCompression"):
			if compression.is_empty() or entry.archiveSha256 != compression.archiveSha256 or entry.sourceCompression.previousPackage != compression.previousPackage:
				return
			marker_identity = compression.previousPackage
		if entry.has("programAuditRestoration"):
			var program := ProgramPackageDelta.correction(entry.campaignId, entry.packageHash)
			if program.is_empty() or marker_identity.archiveSha256 != program.archiveSha256 or entry.programAuditRestoration.previousPackage != program.previousPackage:
				return
			marker_identity = program.previousPackage
		if entry.has("programRestoration"):
			var payment := PaymentSaveUpdate.restoration()
			if payment.is_empty() or entry.campaignId != payment.campaignId or marker_identity.packageHash != payment.packageHash or marker_identity.archiveSha256 != payment.archiveSha256 or entry.programRestoration.previousPackage != payment.previousPackage:
				return
			marker_identity = payment.previousPackage
		if refresh.get("operation") != "correct-classic-map-markers" or refresh.get("receiptFile") != "native-map-triggers.json" or previous.get("packageHash") != row.sourcePackageHash or previous.get("archiveSha256") != row.sourceSha256 or marker_identity.get("packageHash") != row.outputPackageHash or marker_identity.get("archiveSha256") != row.outputSha256:
			return
		var transition_entry := entry.duplicate(true)
		transition_entry["previousPackage"] = previous.duplicate(true)
		transition_entry["correction"] = row.duplicate(true)
		transitions[entry.campaignId] = transition_entry
	_transitions = transitions


func _validate_documents(old_files: Dictionary, new_files: Dictionary, correction: Dictionary) -> bool:
	var old_documents: Dictionary = {}
	var new_documents: Dictionary = {}
	for name: String in DOCUMENTS:
		var before: Variant = JSON.parse_string((old_files[name] as PackedByteArray).get_string_from_utf8())
		var after: Variant = JSON.parse_string((new_files[name] as PackedByteArray).get_string_from_utf8())
		if not before is Dictionary or not after is Dictionary or before.get("schemaVersion") != correction.previousDocuments[name].schemaVersion or after.get("schemaVersion") != 6:
			return false
		old_documents[name] = before
		new_documents[name] = after
	var manifest: Dictionary = JSON.parse_string((new_files["manifest.json"] as PackedByteArray).get_string_from_utf8())
	var program := ProgramPackageDelta.correction(manifest.campaignId, manifest.packageHash)
	if not program.is_empty() and not ProgramPackageDelta.reverse_documents(new_documents, program):
		return false
	for name: String in DOCUMENTS:
		new_documents[name]["schemaVersion"] = old_documents[name].schemaVersion
	var world: Dictionary = new_documents["world.json"]
	var scenario: Dictionary = new_documents["scenario.json"]
	var payment := PaymentSaveUpdate.restoration()
	if correction.outputPackageHash == payment.get("previousPackage", {}).get("packageHash") and not PaymentSaveUpdate.remove_addition(scenario):
		return false
	var maps: Dictionary = {}
	for map: Dictionary in world.maps:
		if not map.has("classicTileValues"):
			return false
		map.erase("classicTileValues")
		maps[map.id] = map
	for change: Dictionary in correction.markerChanges:
		var cell: Array = maps[change.mapId].cells[int(change.cellIndex)]
		if cell[7] != change.correctedFeatures:
			return false
		cell[7] = change.previousFeatures.duplicate(true)
	if not _remove_restored_records(world, scenario, maps, correction):
		return false
	return old_documents == new_documents


func _remove_restored_records(world: Dictionary, scenario: Dictionary, maps: Dictionary, correction: Dictionary) -> bool:
	var records: Array = correction.restoredEmptyRecords.duplicate()
	records.reverse()
	for row: Dictionary in records:
		var triggers: Array = world.triggers.filter(func(trigger: Dictionary) -> bool: return trigger.id == row.id)
		var programs: Array = scenario.programs.filter(func(program: Dictionary) -> bool: return program.id == row.programId)
		if triggers.size() != 1 or programs.size() != 1 or not programs[0].instructions.is_empty():
			return false
		world.triggers.erase(triggers[0])
		scenario.programs.erase(programs[0])
		maps[row.mapId].cells[int(row.cellIndex)][4] = row.previousCellRefs.duplicate()
	var programs_by_id: Dictionary = {}
	for program: Dictionary in scenario.programs:
		programs_by_id[program.id] = program
	if programs_by_id.size() != correction.previousProgramOrder.size():
		return false
	var ordered: Array = []
	for id: String in correction.previousProgramOrder:
		if not programs_by_id.has(id):
			return false
		ordered.append(programs_by_id[id])
	scenario["programs"] = ordered
	return true


func _read_archive(path: String) -> Dictionary:
	var archive := ZIPReader.new()
	if archive.open(path) != OK:
		return {}
	var files: Dictionary = {}
	for name: String in archive.get_files():
		files[name] = archive.read_file(name)
	archive.close()
	return files


func _fail(message: String) -> bool:
	last_error = message
	return false
