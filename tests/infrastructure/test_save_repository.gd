extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const TEST_ROOT: String = "user://realmz2-tests/save-preview-index"
const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")


func run() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	var campaign_id: String = loaded.content.campaign_id
	var campaign_path := TEST_ROOT.path_join(campaign_id)
	_reset_files(campaign_path, ["quick.r2save", "quick.r2save.bak", "mismatch.r2save", "legacy.r2save", "broken.r2save"])
	var session := GameSession.new()
	assert_equal(session.start(loaded.content, 7).state, SessionStep.State.COMPLETED, "save-preview session starts")
	var first := session.snapshot()
	assert_not_null(first, "a committed setup boundary can be indexed")
	if first == null:
		return
	var valid_root := save_data(first)
	var malformed_roots: Array[Dictionary] = []
	var unknown_field := valid_root.duplicate(true)
	unknown_field["unexpected"] = true
	malformed_roots.append({"name": "unknown field", "data": unknown_field})
	var missing_field := valid_root.duplicate(true)
	missing_field.erase("rulesVersion")
	malformed_roots.append({"name": "missing required field", "data": missing_field})
	var unsupported_version := valid_root.duplicate(true)
	unsupported_version["formatVersion"] = 3
	malformed_roots.append({"name": "unsupported version", "data": unsupported_version})
	for malformed: Dictionary in malformed_roots:
		assert_equal(SaveEnvelope.from_data(malformed["data"]), null, "save v4 root rejects %s" % malformed["name"])
	first.game_state.party.add_character(CharacterState.new("preview.hero", "Mira", 10, 10))
	var repository := SaveRepository.new(TEST_ROOT)
	assert_true(repository.save(campaign_id, "quick", first), "the first preview save is installed")
	var second := save_round_trip(first)
	second.game_state.clock.advance_minutes(95)
	assert_true(repository.save(campaign_id, "quick", second), "the second save rotates the first into a backup")
	var mismatch_data: Dictionary = save_data(first)
	mismatch_data["packageHash"] = "f".repeat(64)
	var mismatch := SaveEnvelope.from_data(mismatch_data)
	assert_not_null(mismatch, "a structurally valid package-mismatch fixture is constructed")
	assert_true(repository.save(campaign_id, "mismatch", mismatch), "package mismatch remains a valid untrusted save record")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(campaign_path))
	var legacy_data: Dictionary = save_data(first)
	legacy_data["formatVersion"] = 3
	var legacy := FileAccess.open(campaign_path.path_join("legacy.r2save"), FileAccess.WRITE)
	legacy.store_string(JSON.stringify(legacy_data))
	legacy.close()
	var corrupt := FileAccess.open(campaign_path.path_join("broken.r2save"), FileAccess.WRITE)
	corrupt.store_string("{not-json")
	corrupt.close()
	var previews := repository.list_previews(campaign_id, loaded.content.package_hash)
	assert_equal(previews.size(), 5, "primary, backup, mismatch, incompatible, and corrupt records are indexed independently")
	var host_previews: Array[SaveSlotPreview] = SaveHostController.new(repository).previews(loaded.content)
	assert_equal(host_previews.size(), previews.size(), "the app host preserves the typed save-preview boundary")
	var current := _preview(previews, "quick", SaveSlotPreviewScript.PRIMARY)
	var backup := _preview(previews, "quick", SaveSlotPreviewScript.BACKUP)
	var wrong_package := _preview(previews, "mismatch", SaveSlotPreviewScript.PRIMARY)
	var incompatible := _preview(previews, "legacy", SaveSlotPreviewScript.PRIMARY)
	var broken := _preview(previews, "broken", SaveSlotPreviewScript.PRIMARY)
	assert_not_null(current, "current save preview is present")
	assert_not_null(backup, "rotated backup preview is present")
	assert_not_null(wrong_package, "package mismatch preview is present")
	assert_not_null(incompatible, "incompatible v3 preview is present")
	assert_not_null(broken, "corrupt preview is present")
	if current != null:
		assert_equal([current.status, current.can_load, current.realmz_day, current.realmz_hour, current.realmz_minute, current.map_id, current.character_names], [SaveSlotPreviewScript.VALID, true, 1, 1, 35, "land:0", ["Mira"]], "current preview derives detached campaign facts without mutating the session")
	if backup != null:
		assert_equal([backup.status, backup.can_load, backup.realmz_hour, backup.realmz_minute], [SaveSlotPreviewScript.VALID, true, 0, 0], "backup retains the previous committed boundary")
	if wrong_package != null:
		assert_equal([wrong_package.status, wrong_package.can_load], [SaveSlotPreviewScript.PACKAGE_MISMATCH, false], "package mismatch is visible but cannot be loaded")
	if incompatible != null:
		assert_equal([incompatible.status, incompatible.can_load, incompatible.error_message], [SaveSlotPreviewScript.INCOMPATIBLE, false, "Save format v3 is incompatible with Realmz Rebuilt save v4."], "legacy saves receive an explicit compatibility-cut message")
	if broken != null:
		assert_equal([broken.status, broken.can_load], [SaveSlotPreviewScript.CORRUPT, false], "corrupt saves are visible but cannot be loaded")
	var loaded_backup := repository.load_backup(campaign_id, "quick", loaded.content.package_hash)
	assert_not_null(loaded_backup, "a validated backup can be restored without rewriting the save pair")
	if loaded_backup != null:
		assert_equal(loaded_backup.game_state.clock.total_minutes(), 0, "backup loading returns the exact previous boundary")
	assert_true(repository.load(campaign_id, "mismatch", loaded.content.package_hash) == null and repository.last_error.contains("identity"), "ordinary load continues to reject mismatched immutable content")
	assert_true(repository.load(campaign_id, "legacy", loaded.content.package_hash) == null and repository.last_error == "Save format v3 is incompatible with Realmz Rebuilt save v4.", "ordinary load reports the intentional save compatibility cut")


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
