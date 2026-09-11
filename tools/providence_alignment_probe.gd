## Verifies the pinned Providence application library and shared package fixtures.

extends SceneTree

const CONTRACT_PATH := "res://tests/fixtures/packages/providence_alignment/contract.json"
const EXPECTED_FIXTURE_COMMIT := "e8546ba76472f790a449437db0fbb116bdfee2a2"
const EXPECTED_APPLICATION_COMPILER_COMMIT := "1704ef6b1663eee578bb683b4994cba5cd8c2d88"


func _initialize() -> void:
	var error := _verify_alignment()
	if not error.is_empty():
		printerr("PROVIDENCE_ALIGNMENT_REJECTED %s" % error)
		call_deferred("_quit_cleanly", 1)
		return
	print("PROVIDENCE_ALIGNMENT_ACCEPTED application=%s fixtures=3" % ApplicationLibraryIdentity.PACKAGE_HASH)
	call_deferred("_quit_cleanly", 0)


func _verify_alignment() -> String:
	var contract_value: Variant = _read_json(CONTRACT_PATH)
	var lock_value: Variant = _read_json(ApplicationLibraryIdentity.LOCK_PATH)
	if not contract_value is Dictionary or not lock_value is Dictionary:
		return "The contract or application acceptance lock is invalid JSON."
	var contract: Dictionary = contract_value
	var lock: Dictionary = lock_value
	var identity_error := _verify_identity(contract, lock)
	if not identity_error.is_empty():
		return identity_error
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(
		ApplicationLibraryIdentity.PATH,
		ApplicationLibraryIdentity.CAMPAIGN_ID,
		ApplicationLibraryIdentity.PACKAGE_HASH,
	)
	if not application.is_ok():
		return "Application package failed: %s" % application.error_message
	var count_error := _verify_application_counts(application, lock)
	if not count_error.is_empty():
		return count_error
	for case_value: Variant in contract.get("cases", []):
		if not case_value is Dictionary:
			return "Fixture contract contains a malformed case."
		var case_error := _verify_case(case_value, application)
		if not case_error.is_empty():
			return case_error
	return ""


func _verify_identity(contract: Dictionary, lock: Dictionary) -> String:
	if contract.get("kind") != "providence.rebuilt-alignment-fixtures" or contract.get("formatVersion") != 1:
		return "The fixture contract identity is unsupported."
	if contract.get("providenceCommit") != EXPECTED_FIXTURE_COMMIT:
		return "The fixture Providence commit is not the accepted compiler revision."
	if contract.get("schemaSha256") != PackageRepository.EXPECTED_SCHEMA_HASH:
		return "The fixture schema does not match Rebuilt."
	if contract.get("applicationPackageId") != ApplicationLibraryIdentity.CAMPAIGN_ID or contract.get("applicationPackageHash") != ApplicationLibraryIdentity.PACKAGE_HASH:
		return "The fixture contract does not target the committed application library."
	if lock.get("kind") != "realmz2.application-library-lock" or lock.get("formatVersion") != 1:
		return "The application acceptance lock identity is unsupported."
	if lock.get("compilerCommit") != EXPECTED_APPLICATION_COMPILER_COMMIT:
		return "The application acceptance lock has an unrecognized Providence compiler revision."
	if lock.get("schemaSha256") != PackageRepository.EXPECTED_SCHEMA_HASH:
		return "The application acceptance lock has the wrong package schema."
	if lock.get("packageId") != ApplicationLibraryIdentity.CAMPAIGN_ID or lock.get("packageHash") != ApplicationLibraryIdentity.PACKAGE_HASH:
		return "The application acceptance lock does not match runtime identity."
	var package_path := ProjectSettings.globalize_path(ApplicationLibraryIdentity.PATH)
	var package_file := FileAccess.open(package_path, FileAccess.READ)
	if package_file == null:
		return "The committed application archive is unavailable."
	var package_bytes := package_file.get_length()
	package_file.close()
	if lock.get("archiveBytes") != package_bytes or lock.get("archiveSha256") != _sha256_file(package_path):
		return "The committed application archive does not match its acceptance lock."
	return ""


func _verify_application_counts(application: PackageLoadResult, lock: Dictionary) -> String:
	var counts_value: Variant = lock.get("counts")
	if not counts_value is Dictionary:
		return "The application acceptance lock has no counts."
	var counts: Dictionary = counts_value
	var media_paths: Dictionary = {}
	for asset: MediaAsset in application.media.assets():
		media_paths[asset.path] = true
	var actual := {
		"items": application.content.items.definitions().size(),
		"spells": application.content.magic.definitions().size(),
		"races": application.content.characters.race_definitions().size(),
		"castes": application.content.characters.caste_definitions().size(),
		"mediaDescriptors": application.media.assets().size(),
		"mediaPayloads": media_paths.size(),
	}
	for field: String in actual:
		if counts.get(field) != actual[field]:
			return "Application %s count does not match its acceptance lock." % field
	if counts.get("certifiedCorrections") != 1:
		return "The application lock does not record exactly one certified correction."
	if counts.get("ambiguousMediaResources") != 0 or counts.get("mediaDecodeFailures") != 0:
		return "The application lock records unresolved media."
	var stun := application.content.magic.spell_by_id("classic.spell.2712")
	if stun == null or stun.duration_min != 1 or stun.duration_max != 1 or stun.special != 2:
		return "The application library does not preserve the certified Priest Stun correction."
	return ""


func _verify_case(case_data: Dictionary, application: PackageLoadResult) -> String:
	var case_id: String = case_data.get("id", "")
	var package_path := CONTRACT_PATH.get_base_dir().path_join(String(case_data.get("path", "")))
	if _sha256_file(ProjectSettings.globalize_path(package_path)) != case_data.get("archiveSha256"):
		return "%s archive hash does not match the fixture contract." % case_id
	var inventory_error := _verify_archive_inventory(package_path, case_data)
	if not inventory_error.is_empty():
		return "%s %s" % [case_id, inventory_error]
	var repository := PackageRepository.new()
	repository.set_application_content(application.content, application.media.assets())
	var result := repository.load_package(package_path)
	if result.is_ok() and result.content.package_hash != case_data.get("packageHash"):
		return "%s logical package hash does not match the fixture contract." % case_id
	if case_data.get("expected") == "accepted":
		if not result.is_ok():
			return "%s unexpectedly failed: %s" % [case_id, result.error_message]
		return _verify_positive_overlay(result, application)
	if result.is_ok():
		return "%s unexpectedly passed." % case_id
	if not result.error_message.contains(String(case_data.get("expectedMessageFragment", ""))):
		return "%s failed with the wrong diagnostic: %s" % [case_id, result.error_message]
	return ""


func _verify_archive_inventory(package_path: String, case_data: Dictionary) -> String:
	var content_value: Variant = _read_archive_json(package_path, "content.json")
	var assets_value: Variant = _read_archive_json(package_path, "assets/index.json")
	if not content_value is Dictionary or not assets_value is Dictionary:
		return "does not contain readable content and asset documents."
	var content: Dictionary = content_value
	var assets: Dictionary = assets_value
	if content.get("items", []).size() != case_data.get("scenarioItems") or content.get("spells", []).size() != case_data.get("scenarioSpells"):
		return "contains the wrong scenario definition counts."
	if content.get("races", []).size() + content.get("castes", []).size() != case_data.get("applicationDefinitionsEmbedded"):
		return "duplicates application definitions."
	if assets.get("assets", []).size() != case_data.get("scenarioMedia"):
		return "contains the wrong scenario media count."
	return ""


func _verify_positive_overlay(result: PackageLoadResult, application: PackageLoadResult) -> String:
	var scenario_asset := result.media.asset_by_resource("cicn", 257)
	if scenario_asset == null or scenario_asset.id != "fixture-portrait-257":
		return "positive fixture does not own its exact cicn 257 override."
	var effective := PackageMediaComposer.compose(result.media.assets(), application.media.assets())
	var exact_matches: Array[MediaAsset] = []
	for asset: MediaAsset in effective:
		if asset.resource_type == "cicn" and asset.resource_id == 257:
			exact_matches.append(asset)
	if exact_matches.size() != 1 or exact_matches[0] != scenario_asset:
		return "exact scenario media override did not win effective composition."
	for key: Array in [["cicn", 9000], ["PICT", 300], ["snd ", 147]]:
		if not _has_resource(effective, key[0], key[1]):
			return "application fallback is missing %s:%d." % [key[0], key[1]]
	return ""


func _has_resource(assets: Array[MediaAsset], resource_type: String, resource_id: int) -> bool:
	for asset: MediaAsset in assets:
		if asset.resource_type == resource_type and asset.resource_id == resource_id:
			return true
	return false


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var result: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return result


func _read_archive_json(package_path: String, entry_path: String) -> Variant:
	var archive := ZIPReader.new()
	if archive.open(package_path) != OK:
		return null
	var bytes := archive.read_file(entry_path)
	archive.close()
	return JSON.parse_string(bytes.get_string_from_utf8())


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while file.get_position() < file.get_length():
		if context.update(file.get_buffer(1024 * 1024)) != OK:
			file.close()
			return ""
	file.close()
	return context.finish().hex_encode()


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
