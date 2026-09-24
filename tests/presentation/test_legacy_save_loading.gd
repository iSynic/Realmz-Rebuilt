extends RealmzTestCase

const TEST_ROOT := "user://realmz2-tests/legacy-slot-loading"

class RejectingCopyRepository extends SaveRepository:
	func copy_to_scenario_slot(_campaign: String, _envelope: SaveEnvelope, _target: String = "") -> String:
		last_error = "Injected copy failure."
		return ""

class RejectingPointerRepository extends SaveRepository:
	func set_active_slot(_campaign: String, _slot: String) -> bool:
		last_error = "Injected pointer failure."
		return false

func run() -> void:
	var loaded := load_test_package("res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2")
	if not loaded.is_ok():
		return
	var content := loaded.content
	var folder := TEST_ROOT.path_join(content.campaign_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	var repository := SaveRepository.new(TEST_ROOT)
	var sessions := GameSessionController.new()
	assert_equal(sessions.start(content, 7).state, SessionStep.State.COMPLETED, "legacy fixture starts")
	var original := sessions.session().snapshot()
	var jpeg := Image.create_empty(320, 320, false, Image.FORMAT_RGB8).save_jpg_to_buffer(0.72)
	assert_true(repository.save(content.campaign_id, "quick", original, jpeg), "legacy backup fixture saves")
	original.game_state.clock.advance_minutes(95)
	assert_true(repository.save(content.campaign_id, "quick", original, jpeg), "legacy primary fixture saves")
	var original_hash := FileAccess.get_sha256(folder.path_join("quick.r2save"))
	var backup_hash := FileAccess.get_sha256(folder.path_join("quick.r2save.bak"))
	var shell := load("res://src/ui/shell/game_shell.tscn").instantiate() as GameShell
	(Engine.get_main_loop() as SceneTree).root.add_child(shell)
	shell.present(sessions.view())
	var host := ApplicationAdventureStorageHost.new(SaveHostController.new(repository), sessions, shell, func() -> void: pass)
	for backup: bool in [false, true]:
		var slot := "B" if backup else "A"
		assert_equal(host.load(content, "quick", backup).state, SessionStep.State.COMPLETED, "legacy load assigns first open letter")
		assert_equal(repository.active_slot(content.campaign_id), slot, "successful migration becomes Quick Save target")
		assert_equal(repository.load(content.campaign_id, slot, content.package_hash).to_data(), repository.load_backup(content.campaign_id, "quick", content.package_hash).to_data() if backup else repository.load(content.campaign_id, "quick", content.package_hash).to_data(), "copy preserves complete state, RNG, and JPEG")
	assert_true(host.save(content, "quick"), "ordinary Quick Save uses migrated active slot")
	assert_true(FileAccess.file_exists(folder.path_join("B.r2save.bak")), "Quick Save rotates the assigned letter, not legacy record")
	for index: int in range(2, 10):
		assert_true(repository.save(content.campaign_id, SaveRepository.CLASSIC_SLOTS.substr(index, 1), original), "remaining slots seeded")
	DirAccess.rename_absolute(folder.path_join("C.r2save"), folder.path_join("C.r2save.bak"))
	var corrupt := FileAccess.open(folder.path_join("D.r2save"), FileAccess.WRITE)
	corrupt.store_string("not a save")
	corrupt.close()
	assert_equal(repository.first_empty_slot(content.campaign_id), "", "backup-only and corrupt slots are occupied")
	var unchanged := sessions.session()
	assert_equal(host.load(content, "quick").state, SessionStep.State.FAILED, "full slots require explicit replacement")
	assert_true(sessions.session() == unchanged, "unconfirmed full-slot load leaves adventure unchanged")
	_test_replacement_controls(repository.list_previews(content.campaign_id, content.package_hash))
	assert_equal(host.load(content, "quick", true, "A").state, SessionStep.State.COMPLETED, "confirmed replacement loads legacy backup")
	assert_equal(repository.load_backup(content.campaign_id, "A", content.package_hash).game_state.clock.total_minutes(), 95, "replaced slot retains former primary as backup")
	assert_equal(repository.active_slot(content.campaign_id), "A", "confirmed replacement becomes active")
	unchanged = sessions.session()
	for rejected: SaveRepository in [RejectingCopyRepository.new(TEST_ROOT), RejectingPointerRepository.new(TEST_ROOT)]:
		var failing := ApplicationAdventureStorageHost.new(SaveHostController.new(rejected), sessions, shell, func() -> void: pass)
		assert_equal(failing.load(content, "quick", false, "J").state, SessionStep.State.FAILED, "assignment failure stops restore")
		assert_true(sessions.session() == unchanged and repository.active_slot(content.campaign_id) == "A", "assignment failure does not replace adventure or active pointer")
	assert_true(repository.save(content.campaign_id, "quick-2", original), "second legacy quicksave without JPEG is supported")
	assert_equal(host.load(content, "quick-2", false, "J").state, SessionStep.State.COMPLETED, "second legacy name uses the same assignment route")
	assert_true(repository.load(content.campaign_id, "J", content.package_hash).map_preview_jpeg.is_empty(), "assignment does not invent a missing map preview")
	var invalid := save_round_trip(original)
	invalid.game_state.party.map_id = "missing-map"
	assert_true(repository.save(content.campaign_id, "quick-2", invalid), "semantic-invalid legacy fixture remains structurally valid")
	unchanged = sessions.session()
	var destination_hash := FileAccess.get_sha256(folder.path_join("J.r2save"))
	assert_equal(host.load(content, "quick-2", false, "J").state, SessionStep.State.FAILED, "detached restoration rejects an invalid map before copying")
	assert_true(sessions.session() == unchanged and FileAccess.get_sha256(folder.path_join("J.r2save")) == destination_hash, "failed validation preserves current adventure and destination")
	assert_equal([FileAccess.get_sha256(folder.path_join("quick.r2save")), FileAccess.get_sha256(folder.path_join("quick.r2save.bak"))], [original_hash, backup_hash], "legacy primary and backup remain byte-exact after all operations")
	shell.free()
	sessions.free()

func _test_replacement_controls(previews: Array) -> void:
	var typed: Array[SaveSlotPreview] = []
	typed.assign(previews)
	var controller := SystemScreenController.new()
	controller.set_save_previews(typed)
	var body := VBoxContainer.new()
	controller.present(body, GameView.new(1, true, null), PresentationSettings.new())
	var actions: Array[Dictionary] = []
	controller.action_requested.connect(func(action: StringName, value: Variant) -> void: actions.append({"action": action, "value": value}))
	var legacy := body.find_child("SavePreview_quick_backup", true, false) as Button
	var load_button := body.find_child("LoadSelectedSave", true, false) as Button
	var confirm := body.find_child("Confirm", true, false) as Button
	legacy.pressed.emit()
	load_button.pressed.emit()
	assert_true(confirm.disabled and actions.is_empty(), "full-slot load waits for destination selection")
	(body.find_child("SavePreview_J_primary", true, false) as Button).pressed.emit()
	assert_false(confirm.disabled, "choosing a letter enables explicit confirmation")
	(body.find_child("Cancel", true, false) as Button).pressed.emit()
	assert_true(actions.is_empty() and not load_button.disabled, "Cancel issues no host operation and restores browsing")
	legacy.pressed.emit()
	load_button.pressed.emit()
	(body.find_child("SavePreview_A_primary", true, false) as Button).pressed.emit()
	assert_true(actions.is_empty(), "destination selection alone cannot replace a save")
	confirm.pressed.emit()
	assert_equal(actions, [{"action": &"load_legacy_into_slot", "value": {"slotId": "quick", "backup": true, "targetSlotId": "A"}}], "confirmation emits exact legacy source and destination once")
	body.free()
