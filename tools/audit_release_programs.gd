## Extract only immutable scenario inputs from an explicit exported PCK for comparison.
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or DirAccess.dir_exists_absolute(args[1]):
		push_error("Expected an absolute PCK path and a new absolute evidence directory.")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(args[0], true):
		quit(1)
		return
	var bundle := "res://src/storage/packages/bundled_campaigns/"
	var catalog_path := bundle + "castle-bundled-scenarios.provenance.json"
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not catalog is Dictionary or catalog.get("scenarios", []).size() != 13:
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		quit(1)
		return
	if FileAccess.file_exists(bundle + "program-restoration.json") or FileAccess.file_exists(bundle + "program-inventory.json") or FileAccess.file_exists(bundle + "program-audit-findings.json"):
		push_error("Export contains an uncompressed repair receipt or maintainer-only audit report.")
		quit(1)
		return
	for name: String in ["complete-records.json", "complete-records-inventory.json", "complete-records-baseline.provenance.json"]:
		if FileAccess.file_exists(bundle + name):
			push_error("Export contains maintainer-only complete-record evidence.")
			quit(1)
			return
	var receipt_names: Array[String] = ["program-restoration.json.zlib", "source-compression.json", "castle-bundled-scenarios.provenance.json"]
	if FileAccess.file_exists(bundle + "complete-records.json.zlib"):
		receipt_names.append("complete-records.json.zlib")
	for name: String in receipt_names:
		if not FileAccess.file_exists(bundle + name):
			quit(1)
			return
		var copy := FileAccess.open(args[1].path_join(name), FileAccess.WRITE)
		if copy == null:
			quit(1)
			return
		copy.store_buffer(FileAccess.get_file_as_bytes(bundle + name))
		copy.close()
	var records: Array = []
	var identities: Dictionary = {}
	for row: Dictionary in catalog.scenarios:
		var source := bundle + String(row.file)
		var digest := FileAccess.get_sha256(source)
		if digest != row.archiveSha256 or String(row.file).get_file() != row.file or row.campaignId != String(row.file).trim_suffix(".realmz2") or identities.has(row.campaignId):
			quit(1)
			return
		identities[row.campaignId] = true
		var output := FileAccess.open(args[1].path_join(row.file), FileAccess.WRITE)
		if output == null:
			quit(1)
			return
		output.store_buffer(FileAccess.get_file_as_bytes(source))
		output.close()
		records.append({"campaignId": row.campaignId, "file": row.file, "archiveSha256": digest, "packageHash": row.packageHash})
	var report := FileAccess.open(args[1].path_join("payload-inventory.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"kind": "realmz-rebuilt.exported-program-inputs", "formatVersion": 1, "pckSha256": FileAccess.get_sha256(args[0]), "campaigns": records}, "\t"))
	report.close()
	quit(0)
