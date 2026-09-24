extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const TEST_ROOT: String = "user://realmz2-tests/save-preview-index"
const SaveSlotPreviewScript := preload("res://src/playthrough/session/save_slot_preview.gd")


func run() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	var campaign_id: String = loaded.content.campaign_id
	var campaign_path := TEST_ROOT.path_join(campaign_id)
	_reset_files(campaign_path, ["quick.r2save", "quick.r2save.bak", "mismatch.r2save", "legacy.r2save", "broken.r2save", "updated.r2save", "updated.r2save.tmp", "updated.r2save.bak", "active-slot", "active-slot.bak"])
	var session := GameSession.new()
	assert_equal(session.start(loaded.content, 7).state, SessionStep.State.COMPLETED, "save-preview session starts")
	var first := session.snapshot()
	if first == null:
		return
	var valid_root := save_data(first)
	var malformed_roots: Array[Dictionary] = []
	malformed_roots.append({"name": "unknown field", "data": valid_root.merged({"unexpected": true})})
	malformed_roots.append({"name": "invalid JPEG preview", "data": valid_root.merged({"mapPreviewJpeg": "bm90IGEganBlZw=="})})
	var missing_field := valid_root.duplicate(true)
	missing_field.erase("rulesVersion")
	malformed_roots.append({"name": "missing required field", "data": missing_field})
	var unsupported_version := valid_root.duplicate(true)
	unsupported_version["formatVersion"] = 4
	malformed_roots.append({"name": "unsupported version", "data": unsupported_version})
	for malformed: Dictionary in malformed_roots:
		assert_equal(SaveEnvelope.from_data(malformed["data"]), null, "save v5 root rejects %s" % malformed["name"])
	first.game_state.party.add_character(CharacterState.new("preview.hero", "Mira", 10, 10))
	first.game_state.experience_multiplier = 1.0 / 3.0
	var repository := SaveRepository.new(TEST_ROOT)
	var preview_jpeg := Image.create_empty(320, 320, false, Image.FORMAT_RGB8).save_jpg_to_buffer(0.72)
	assert_true(repository.save(campaign_id, "quick", first, preview_jpeg), "the first preview save is installed with its 320×320 JPEG")
	assert_true(repository.set_active_slot(campaign_id, "C") and SaveRepository.new(TEST_ROOT).active_slot(campaign_id) == "C", "the active A–J slot survives repository restart")
	assert_false(repository.set_active_slot(campaign_id, "K"), "an out-of-range slot cannot become the Quick Save target")
	var second := save_round_trip(first)
	second.game_state.clock.advance_minutes(95)
	assert_true(repository.save(campaign_id, "quick", second, preview_jpeg), "the second save rotates the first into a backup")
	var mismatch_data: Dictionary = save_data(first)
	mismatch_data["packageHash"] = "f".repeat(64)
	var mismatch := SaveEnvelope.from_data(mismatch_data)
	assert_not_null(mismatch, "a structurally valid package-mismatch fixture is constructed")
	assert_true(repository.save(campaign_id, "mismatch", mismatch), "package mismatch remains a valid untrusted save record")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(campaign_path))
	var legacy_data: Dictionary = save_data(first)
	legacy_data["formatVersion"] = 4
	var legacy := FileAccess.open(campaign_path.path_join("legacy.r2save"), FileAccess.WRITE)
	legacy.store_string(JSON.stringify(legacy_data))
	legacy.close()
	var corrupt := FileAccess.open(campaign_path.path_join("broken.r2save"), FileAccess.WRITE)
	corrupt.store_string("{not-json")
	corrupt.close()
	var previews := repository.list_previews(campaign_id, loaded.content.package_hash)
	assert_equal(previews.size(), 5, "primary, backup, mismatch, incompatible, and corrupt records are indexed independently")
	var current := _preview(previews, "quick", SaveSlotPreviewScript.PRIMARY)
	var backup := _preview(previews, "quick", SaveSlotPreviewScript.BACKUP)
	var wrong_package := _preview(previews, "mismatch", SaveSlotPreviewScript.PRIMARY)
	var incompatible := _preview(previews, "legacy", SaveSlotPreviewScript.PRIMARY)
	var broken := _preview(previews, "broken", SaveSlotPreviewScript.PRIMARY)
	assert_not_null(backup, "rotated backup preview is present")
	assert_not_null(wrong_package, "package mismatch preview is present")
	assert_not_null(incompatible, "incompatible v3 preview is present")
	assert_not_null(broken, "corrupt preview is present")
	if current != null:
		assert_equal([current.status, current.can_load, current.realmz_day, current.realmz_hour, current.realmz_minute, current.map_id, current.character_names, current.map_preview_jpeg], [SaveSlotPreviewScript.VALID, true, 1, 1, 35, "land:0", ["Mira"], preview_jpeg], "current preview derives detached campaign facts and JPEG without mutating the session")
	if backup != null:
		assert_equal([backup.status, backup.can_load, backup.realmz_hour, backup.realmz_minute, backup.map_preview_jpeg], [SaveSlotPreviewScript.VALID, true, 0, 0, preview_jpeg], "backup retains the previous committed boundary and map JPEG")
	if wrong_package != null:
		assert_equal([wrong_package.status, wrong_package.can_load], [SaveSlotPreviewScript.PACKAGE_MISMATCH, false], "package mismatch is visible but cannot be loaded")
	if incompatible != null:
		assert_equal([incompatible.status, incompatible.can_load, incompatible.error_message], [SaveSlotPreviewScript.INCOMPATIBLE, false, "Save format v4 is incompatible with Realmz Rebuilt save v5."], "legacy saves receive an explicit compatibility-cut message")
	if broken != null:
		assert_equal([broken.status, broken.can_load], [SaveSlotPreviewScript.CORRUPT, false], "corrupt saves are visible but cannot be loaded")
	var loaded_backup := repository.load_backup(campaign_id, "quick", loaded.content.package_hash)
	assert_not_null(loaded_backup, "a validated backup can be restored without rewriting the save pair")
	if loaded_backup != null:
		assert_equal([loaded_backup.game_state.clock.total_minutes(), var_to_bytes(loaded_backup.game_state.experience_multiplier), PartySetupRules.scale_experience_by_multiplier(600, loaded_backup.game_state.experience_multiplier)], [0, var_to_bytes(first.game_state.experience_multiplier), 200], "backup loading preserves the previous boundary and exact fractional reward multiplier")
	assert_true(repository.load(campaign_id, "mismatch", loaded.content.package_hash) == null and repository.last_error.contains("identity"), "ordinary load continues to reject mismatched immutable content")
	assert_true(repository.load(campaign_id, "legacy", loaded.content.package_hash) == null and repository.last_error == "Save format v4 is incompatible with Realmz Rebuilt save v5.", "ordinary load reports the intentional save compatibility cut")
	var original_before := FileAccess.get_sha256(campaign_path.path_join("quick.r2save"))
	var backup_before := FileAccess.get_sha256(campaign_path.path_join("quick.r2save.bak"))
	var update_copy := SaveEnvelope.from_data(save_data(first).merged({"mapPreviewJpeg": Marshalls.raw_to_base64(preview_jpeg)}))
	assert_true(repository.save_new_copy(campaign_id, "updated", update_copy), "an explicit copy installs into a separate empty slot")
	assert_equal(repository.load(campaign_id, "updated", loaded.content.package_hash).to_data(), update_copy.to_data(), "the copied save round-trips every state and RNG field")
	assert_true(repository.save_new_copy(campaign_id, "updated", update_copy), "retrying the same completed copy is idempotent")
	assert_false(repository.save_new_copy(campaign_id, "updated", SaveEnvelope.from_data(save_data(second))), "a different copy cannot overwrite the first completed copy")
	assert_equal([FileAccess.get_sha256(campaign_path.path_join("quick.r2save")), FileAccess.get_sha256(campaign_path.path_join("quick.r2save.bak")), FileAccess.file_exists(campaign_path.path_join("updated.r2save.bak"))], [original_before, backup_before, false], "copy retries and collisions preserve the original, backup, and copied-slot backup boundary")


func _preview(previews: Array, slot_id: String, source: StringName) -> RefCounted:
	for preview: RefCounted in previews:
		if preview.slot_id == slot_id and preview.source == source:
			return preview
	return null


func _reset_files(campaign_path: String, file_names: Array[String]) -> void:
	for file_name: String in file_names:
		var path := campaign_path.path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
