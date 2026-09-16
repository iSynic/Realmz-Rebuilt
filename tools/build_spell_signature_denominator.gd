extends SceneTree

const PERFORMANCE_PACKAGE_LOADER := preload("res://tools/performance_package_loader.gd")
const APPLICATION_PACKAGE_PATH := ApplicationLibraryIdentity.PATH
const APPLICATION_PACKAGE_ID := ApplicationLibraryIdentity.CAMPAIGN_ID
const APPLICATION_PACKAGE_HASH := ApplicationLibraryIdentity.PACKAGE_HASH
const OUTPUT_PATH := "res://tests/fixtures/oracle/classic-spell-signature-denominator.json"

const CONVERSION_BLOCKED_NAMES := [
	"Araman's Ring",
	"Begining of the End",
	"Dagger of Shine",
	"Elemental Strife",
	"Hax",
	"Kalypso's Island",
	"Lachis",
	"Search for the Lost City",
	"Spires of Steel",
	"Trial by Fire",
]

const OPENING_TESTED_NAMES := [
	"City of Port Hyrtin",
	"Journey into the Mire",
]

const BUNDLED_DONOR_NAMES := [
	"Assault On Giant Mountain",
	"Castle in the Clouds",
	"City Of Bywater",
	"Destroy The Necronomicon",
	"Grilochs Revenge",
	"Half Truth",
	"Mithril Vault",
	"Prelude To Pestilence",
	"Trouble in the Sword Lands",
	"Twin Sands of Time",
	"War in the Sword Lands",
	"White Dragon",
	"Wrath of the Mind Lords",
]

func _initialize() -> void:
	var write := "--write" in OS.get_cmdline_user_args()
	var repository := PackageRepository.new()
	var app_load := repository.load_bundled_package(APPLICATION_PACKAGE_PATH, APPLICATION_PACKAGE_ID, APPLICATION_PACKAGE_HASH)
	if not app_load.is_ok():
		printerr("Failed to load application package: %s" % app_load.error_message)
		quit(1)
		return

	var app_content: RealmzContent = app_load.content
	var signatures_by_id: Dictionary = {}
	var scanned_sources: Array[Dictionary] = []

	# 1. Stock Application Library spells
	var app_file := FileAccess.open(APPLICATION_PACKAGE_PATH, FileAccess.READ)
	var app_file_size := 0
	if app_file != null:
		app_file_size = app_file.get_length()
		app_file.close()
	var app_file_sha256 := FileAccess.get_sha256(APPLICATION_PACKAGE_PATH)

	for spell: SpellDefinition in app_content.magic.definitions():
		_register_spell(spell, "stock:application", signatures_by_id)

	scanned_sources.append({
		"activeSpellCount": app_content.magic.definitions().size(),
		"campaignId": APPLICATION_PACKAGE_ID,
		"category": "stock-application",
		"compilerStatus": "stock-application",
		"hasDataSpell": true,
		"name": "realmz-classic-application-library",
		"packageHash": APPLICATION_PACKAGE_HASH,
		"path": APPLICATION_PACKAGE_PATH,
		"sha256": app_file_sha256,
		"sizeBytes": app_file_size,
		"status": "verified",
	})

	# 2. Bundled Packages (sorted by scenarioId)
	var bundled_dir := "res://src/storage/packages/bundled_campaigns"
	var dir := DirAccess.open(bundled_dir)
	var bundled_files: Array[String] = []
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if file_name.ends_with(".realmz2"):
				bundled_files.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	bundled_files.sort()

	for b_name in bundled_files:
		print("Processing bundled package: %s" % b_name)
		var full_path := bundled_dir + "/" + b_name
		var scenario_id: String = b_name.trim_suffix(".realmz2").trim_prefix("scenario-")
		var b_file := FileAccess.open(full_path, FileAccess.READ)
		var b_size := 0
		if b_file != null:
			b_size = b_file.get_length()
			b_file.close()
		var b_sha256 := FileAccess.get_sha256(full_path)

		var loaded := PERFORMANCE_PACKAGE_LOADER.load_scenario(full_path, app_load)
		var scenario_spells := 0
		if loaded.is_ok():
			for spell: SpellDefinition in loaded.content.magic.definitions():
				var role := String(ClassicSpellIdentityCatalog.application_role(spell))
				if role == String(ClassicSpellIdentityCatalog.ROLE_UNKNOWN):
					scenario_spells += 1
					_register_spell(spell, "bundled:%s" % scenario_id, signatures_by_id)
			scanned_sources.append({
				"activeSpellCount": scenario_spells,
				"campaignId": scenario_id,
				"category": "bundled-package",
				"compilerStatus": "bundled",
				"hasDataSpell": true,
				"name": scenario_id,
				"packageHash": loaded.content.package_hash,
				"path": full_path,
				"sha256": b_sha256,
				"sizeBytes": b_size,
				"status": "verified",
			})
		else:
			scanned_sources.append({
				"activeSpellCount": 0,
				"campaignId": scenario_id,
				"category": "bundled-package",
				"compilerStatus": "load-error",
				"hasDataSpell": false,
				"name": scenario_id,
				"packageHash": "",
				"path": full_path,
				"sha256": b_sha256,
				"sizeBytes": b_size,
				"status": "load-error: %s" % loaded.error_message,
			})
			printerr("Failed to load bundled package %s: %s" % [b_name, loaded.error_message])

	# 3. Raw scenarios in F:/Scenarios (sorted deterministically)
	var raw_root := "F:/Scenarios"
	var raw_dir := DirAccess.open(raw_root)
	var scenario_dirs: Array[String] = []
	if raw_dir != null:
		raw_dir.list_dir_begin()
		var s_name := raw_dir.get_next()
		while not s_name.is_empty():
			if raw_dir.current_is_dir() and not s_name.begins_with("."):
				scenario_dirs.append(s_name)
			s_name = raw_dir.get_next()
		raw_dir.list_dir_end()
	scenario_dirs.sort()

	for s_name in scenario_dirs:
		var spell_file_path := "%s/%s/Data Spell" % [raw_root, s_name]
		var compiler_status := "auxiliary-source"
		if CONVERSION_BLOCKED_NAMES.has(s_name):
			compiler_status = "conversion-blocked"
		elif OPENING_TESTED_NAMES.has(s_name):
			compiler_status = "opening-tested"
		elif BUNDLED_DONOR_NAMES.has(s_name):
			compiler_status = "bundled-donor"

		if FileAccess.file_exists(spell_file_path):
			var parse_result: Dictionary = _process_raw_data_spell(spell_file_path, s_name, signatures_by_id)
			scanned_sources.append({
				"activeSpellCount": parse_result["activeCount"],
				"campaignId": s_name,
				"category": "raw-scenario",
				"compilerStatus": compiler_status,
				"hasDataSpell": true,
				"name": s_name,
				"packageHash": "",
				"path": spell_file_path,
				"sha256": parse_result["sha256"],
				"sizeBytes": parse_result["size"],
				"status": parse_result["status"],
			})
		else:
			scanned_sources.append({
				"activeSpellCount": 0,
				"campaignId": s_name,
				"category": "raw-scenario",
				"compilerStatus": compiler_status,
				"hasDataSpell": false,
				"name": s_name,
				"packageHash": "",
				"path": spell_file_path,
				"sha256": "",
				"sizeBytes": 0,
				"status": "absent-inherits-stock",
			})

	repository.close()

	# Build result
	var result := _build_denominator(signatures_by_id, scanned_sources)
	var json_text := CanonicalJson.encode(result) + "\n"

	print("Authoritative Classic Spell Signature Denominator:")
	print("  Total unique behavior signatures: %d" % result["summary"]["totalUniqueSignatures"])
	print("  Implemented: %d" % result["summary"]["dispositionCounts"]["implemented"])
	print("  Not Applicable: %d" % result["summary"]["dispositionCounts"]["not-applicable"])
	print("  Malformed Safe: %d" % result["summary"]["dispositionCounts"]["malformed-safe"])
	print("  Pending Runtime Gaps: %d" % result["summary"]["dispositionCounts"]["pending-runtime-gap"])
	print("  Scanned sources: %d (verified: %d)" % [scanned_sources.size(), _count_verified_sources(scanned_sources)])

	if write:
		var f := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
		if f == null:
			printerr("Failed to open %s for writing" % OUTPUT_PATH)
			quit(1)
			return
		f.store_string(json_text)
		f.close()
		print("Wrote denominator to %s" % OUTPUT_PATH)
	else:
		if not FileAccess.file_exists(OUTPUT_PATH):
			printerr("Denominator file does not exist: %s" % OUTPUT_PATH)
			quit(1)
			return
		var existing := FileAccess.get_file_as_string(OUTPUT_PATH)
		if existing != json_text:
			printerr("Denominator file is out of date: %s" % OUTPUT_PATH)
			quit(1)
			return
		print("Denominator verified against %s" % OUTPUT_PATH)

	quit(0)


func _count_verified_sources(sources: Array[Dictionary]) -> int:
	var count := 0
	for src in sources:
		if src["status"] == "verified":
			count += 1
	return count


func _register_spell(spell: SpellDefinition, source_tag: String, signatures_by_id: Dictionary) -> void:
	var behavior: Dictionary = ClassicSpellClassificationRules.behavior_signature(spell)
	var signature_id := CanonicalJson.encode(behavior).sha256_text().substr(0, 16)
	var family := String(ClassicSpellClassificationRules.mechanical_family(spell))
	var contexts: Dictionary = ClassicSpellDispositionRules.runtime_contexts(spell)

	var record: Dictionary = signatures_by_id.get(signature_id, {
		"behavior": behavior,
		"classicIds": [],
		"family": family,
		"names": [],
		"runtimeContexts": contexts,
		"signatureId": signature_id,
		"sources": [],
	})

	var source_entry := "%s:%s" % [source_tag, spell.id]
	if not record["sources"].has(source_entry):
		record["sources"].append(source_entry)
	if not record["classicIds"].has(spell.classic_id):
		record["classicIds"].append(spell.classic_id)
	if not spell.name.is_empty() and not record["names"].has(spell.name):
		record["names"].append(spell.name)

	signatures_by_id[signature_id] = record


func _process_raw_data_spell(path: String, scenario_name: String, signatures_by_id: Dictionary) -> Dictionary:
	var sha256 := FileAccess.get_sha256(path)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"activeCount": 0, "sha256": "", "size": 0, "status": "unreadable"}
	var file_length := f.get_length()
	if file_length < 3150:
		f.close()
		return {"activeCount": 0, "sha256": sha256, "size": file_length, "status": "malformed-length-too-short"}
	var bytes := f.get_buffer(file_length)
	f.close()

	# Validate trailing padding bytes
	var trailing_clean := true
	for idx in range(3150, file_length):
		if bytes[idx] != 0:
			trailing_clean = false
			break

	if not trailing_clean:
		return {"activeCount": 0, "sha256": sha256, "size": file_length, "status": "malformed-nonzero-trailing-padding"}

	var active_count := 0
	for i in range(105):
		var offset := i * 30
		var b := bytes.slice(offset, offset + 30)

		# Check if entirely zero / unused
		var all_zero := true
		for byte_val in b:
			if byte_val != 0:
				all_zero = false
				break
		if all_zero:
			continue

		active_count += 1
		var classic_id := 5000 + (int(i / 15) + 1) * 100 + (i % 15) + 1
		var spell := SpellDefinition.new("classic.spell.%d" % classic_id, classic_id, "Custom Spell %d" % classic_id)
		spell.range_min = b[0] if b[0] < 128 else b[0] - 256
		spell.range_max = b[1] if b[1] < 128 else b[1] - 256
		spell.queue_icon = b[2] if b[2] < 128 else b[2] - 256
		spell.to_hit_bonus = b[3] if b[3] < 128 else b[3] - 256
		spell.save_bonus = b[4] if b[4] < 128 else b[4] - 256
		spell.fixed_target_count = b[5] if b[5] < 128 else b[5] - 256
		spell.can_rotate = (b[6] != 0)
		spell.save_adjust = b[7] if b[7] < 128 else b[7] - 256
		spell.cannot = b[8] if b[8] < 128 else b[8] - 256
		spell.resistance_adjust = b[9] if b[9] < 128 else b[9] - 256
		spell.cost = b[10] if b[10] < 128 else b[10] - 256
		spell.damage_min = b[11] if b[11] < 128 else b[11] - 256
		spell.damage_max = b[12] if b[12] < 128 else b[12] - 256
		spell.power_damage_min = b[13] if b[13] < 128 else b[13] - 256
		spell.power_damage_max = b[14] if b[14] < 128 else b[14] - 256
		spell.duration_min = b[15] if b[15] < 128 else b[15] - 256
		spell.duration_max = b[16] if b[16] < 128 else b[16] - 256
		spell.power_duration_min = b[17] if b[17] < 128 else b[17] - 256
		spell.power_duration_max = b[18] if b[18] < 128 else b[18] - 256
		spell.look_start = b[19] if b[19] < 128 else b[19] - 256
		spell.look_end = b[20] if b[20] < 128 else b[20] - 256
		spell.sound_start = b[21] if b[21] < 128 else b[21] - 256
		spell.sound_end = b[22] if b[22] < 128 else b[22] - 256
		spell.target_type = b[23] if b[23] < 128 else b[23] - 256
		spell.size = b[24] if b[24] < 128 else b[24] - 256
		spell.special = b[25]
		spell.damage_type = b[26] if b[26] < 128 else b[26] - 256
		spell.spell_class = b[27]
		spell.in_combat = (b[28] != 0)
		spell.in_camp = (b[29] != 0)

		_register_spell(spell, "raw:%s" % scenario_name, signatures_by_id)

	return {"activeCount": active_count, "sha256": sha256, "size": file_length, "status": "verified"}


func _build_denominator(signatures_by_id: Dictionary, scanned_sources: Array[Dictionary]) -> Dictionary:
	var signatures: Array[Dictionary] = []
	var counts := {
		"implemented": 0,
		"malformed-safe": 0,
		"not-applicable": 0,
		"pending-runtime-gap": 0,
	}
	var family_counts: Dictionary = {}

	var sorted_ids: Array = signatures_by_id.keys()
	sorted_ids.sort()

	for signature_id: String in sorted_ids:
		var rec: Dictionary = signatures_by_id[signature_id]
		var behavior: Dictionary = rec["behavior"]
		var contexts: Dictionary = rec["runtimeContexts"]
		var family: String = rec["family"]
		family_counts[family] = int(family_counts.get(family, 0)) + 1

		# Classify disposition: keep compiler readiness separate from runtime capability
		var disposition := ""
		var reason := ""

		var is_all_not_applicable := true
		var has_executable := false
		var has_pending := false
		var pending_contexts: Array[String] = []
		for ctx_name: String in contexts:
			var ctx_disp: String = contexts[ctx_name]
			if ctx_disp == String(ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE):
				has_executable = true
				is_all_not_applicable = false
			elif ctx_disp == String(ClassicSpellDispositionRules.DISPOSITION_PENDING):
				has_pending = true
				is_all_not_applicable = false
				pending_contexts.append(ctx_name)

		# Check if malformed (targetType 0, size > 0, special != 58)
		var is_malformed: bool = (int(behavior["targetType"]) == 0 and int(behavior["size"]) > 0 and int(behavior["special"]) != 58)

		var sorted_sources: Array = rec["sources"]
		sorted_sources.sort()
		var sorted_classic_ids: Array = rec["classicIds"]
		sorted_classic_ids.sort()
		var sorted_names: Array = rec["names"]
		sorted_names.sort()

		if is_malformed:
			disposition = "malformed-safe"
			reason = "Target type 0 with nonzero size and non-summon special is malformed under CCG-008; safely rejected with typed diagnostic."
		elif is_all_not_applicable:
			disposition = "not-applicable"
			reason = "Spell is non-combat, reserved standard slot, or not applicable to any combat runtime context."
		elif has_pending:
			disposition = "pending-runtime-gap"
			pending_contexts.sort()
			reason = "Valid signature contains unsupported runtime contexts: %s (sources: %s)." % [", ".join(pending_contexts), ", ".join(sorted_sources)]
		else:
			disposition = "implemented"
			reason = "All applicable runtime contexts are executable in Rebuilt."

		counts[disposition] = int(counts.get(disposition, 0)) + 1

		var entry: Dictionary = {
			"behavior": behavior,
			"classicIds": sorted_classic_ids,
			"disposition": disposition,
			"dispositionReason": reason,
			"family": family,
			"names": sorted_names,
			"runtimeContexts": contexts,
			"signatureId": signature_id,
			"sources": sorted_sources,
		}
		signatures.append(entry)

	# Sort scanned sources deterministically by category, then name
	scanned_sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["category"] != b["category"]:
			return a["category"] < b["category"]
		return a["name"] < b["name"]
	)

	return {
		"formatVersion": 2,
		"scannedSources": scanned_sources,
		"signatures": signatures,
		"summary": {
			"dispositionCounts": counts,
			"familyCounts": family_counts,
			"scannedSourceCount": scanned_sources.size(),
			"totalUniqueSignatures": signatures.size(),
		}
	}
