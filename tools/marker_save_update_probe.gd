## Isolated save-copy acceptance using retained stock archives and new scratch storage.
extends SceneTree

var _checks := 0
var _failures := 0
var _results: Array[Dictionary] = []
var _save_root: String


class WriteFailureRepository extends SaveRepository:
	func save_new_copy(_campaign: String, _slot: String, _envelope: SaveEnvelope) -> bool:
		last_error = "Injected scratch write failure."
		return false


class ReadbackFailureRepository extends SaveRepository:
	func load(_campaign: String, _slot: String, _expected_hash: String) -> SaveEnvelope:
		last_error = "Injected scratch readback failure."
		return null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path() or DirAccess.dir_exists_absolute(args[1]) or FileAccess.file_exists(args[1]):
		printerr("Usage: -- <retained-original-directory> <new-absolute-scratch-directory>")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(args[1]) != OK:
		quit(2)
		return
	print("ISOLATED: thirteen pinned stock marker save updates; scratch packages/saves only")
	_save_root = args[1].path_join("saves")
	var repository := PackageRepository.new()
	var app := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not _check(app.is_ok(), "application loads"):
		quit(1)
		return
	repository.set_application_content(app.content, app.media.assets())
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MarkerSaveUpdate.CATALOG_PATH))
	for entry: Dictionary in catalog.scenarios:
		_check_campaign(repository, entry, args[0], args[1])
	repository.close()
	var output := FileAccess.open(args[1].path_join("result.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "campaigns": _results}, "\t"))
	output.close()
	print("MARKER_SAVE_UPDATE checks=%d failures=%d" % [_checks, _failures])
	call_deferred("quit", 0 if _failures == 0 else 1)


func _check_campaign(repository: PackageRepository, entry: Dictionary, originals: String, scratch: String) -> void:
	var failures_before := _failures
	var installed_root := scratch.path_join("packages")
	var source_path := originals.path_join(entry.file)
	var source_hash := FileAccess.get_sha256(source_path)
	if not _check(source_hash == entry.nativeTileRefresh.previousPackage.archiveSha256, "retained original matches approved bytes"):
		return
	var installed := repository.install_package(source_path, installed_root)
	if not _check(installed.is_ok(), "original installs: " + installed.error_message):
		return
	var loaded := repository.load_package(MarkerSaveUpdate.BUNDLE_ROOT.path_join(entry.file))
	if not _check(loaded.is_ok(), "current package loads: " + loaded.error_message):
		return
	var old_content := installed.package.content
	var current := loaded.content
	var session := _prepared_session(old_content)
	if session == null:
		return
	var saves := SaveRepository.new(_save_root)
	var policy := MarkerSaveUpdate.new(installed_root)
	var host := SaveHostController.new(saves, null, null, policy)
	var jpeg := Image.create_empty(320, 320, false, Image.FORMAT_RGB8).save_jpg_to_buffer(0.72)
	_check(host.save(old_content, "A", session.snapshot(), jpeg), "primary writes with thumbnail")
	var snapshot := session.snapshot()
	snapshot.game_state.party.fatigue = 24
	_check(session.restore(old_content, snapshot).state == SessionStep.State.COMPLETED, "second boundary restores")
	_check(host.save(old_content, "A", session.snapshot(), jpeg), "second save retains original backup")
	_check(host.set_active_slot(old_content, "J"), "scratch Quick Save target set")
	var active_before := SaveEnvelope.from_snapshot(session.snapshot()).to_data()
	_check(host.load(current, "A") == null, "ordinary mismatched load rejects")
	_check(host.previews(current).filter(func(preview: SaveSlotPreview) -> bool: return preview.slot_id == "A" and preview.can_update).size() == 2, "primary and backup offer Update Save")
	for backup: bool in [false, true]:
		_verify_copy(host, saves, old_content, current, "A", backup)
	_check(SaveEnvelope.from_snapshot(session.snapshot()).to_data() == active_before and host.active_slot(current) == "J", "active adventure and Quick Save target stay unchanged")
	_check(not policy.eligible(entry.campaignId, "f".repeat(64), entry.packageHash) and not policy.eligible("imported-example", old_content.package_hash, entry.packageHash), "unlisted predecessor and imported campaign reject")
	_check(FileAccess.get_sha256(source_path) == source_hash and FileAccess.get_sha256(installed.installed_path) == source_hash, "retained and installed originals stay byte-identical")
	if entry.campaignId == "scenario-city-of-bywater":
		_check_failures(repository, host, saves, old_content, current, source_path, installed_root, scratch)
		_check_artwork(host, saves, session, old_content, current)
		_check_pending_shop(host, saves, session, old_content, current)
	_results.append({"campaignId": entry.campaignId, "oldPackageHash": old_content.package_hash, "newPackageHash": current.package_hash, "passed": _failures == failures_before})
	print("MARKER_SAVE_UPDATE campaign=%s complete failures=%d" % [entry.campaignId, _failures - failures_before])


func _prepared_session(content: RealmzContent) -> GameSession:
	var session := GameSession.new()
	if not _check(session.start(content, 853).state == SessionStep.State.COMPLETED, "old campaign starts"):
		return null
	var snapshot := session.snapshot()
	var catalog := ClassicStarterCharacterCatalog.new()
	var records := catalog.load_records(CharacterVaultController.CLASSIC_STARTER_CATALOG_PATH, ApplicationLibraryIdentity.PACKAGE_HASH)
	var rules := RealmzRules.new()
	for record: CharacterVaultRecord in records:
		var character := CharacterStateCodec.copy(record.state)
		# Normal stock admission recalculates load against destination item definitions.
		character.carried_load = rules.inventory.calculated_load(character, content.items.definitions())
		snapshot.game_state.party.add_character(character)
	snapshot.game_state.party_setup_completed = true
	snapshot.game_state.party.fatigue = 23
	snapshot.game_state.scenario_progress.set_quest_value(0, -1)
	snapshot.game_state.scenario_progress.set_quest_value(99, 32767)
	snapshot.game_state.world.topology.replace_terrain(content.start_map_id, content.start_coordinate, "classic.terrain.60")
	for index: int in range(100):
		var trigger := content.scenario_records.trigger_by_map_record(content.start_map_id, index)
		if trigger != null:
			snapshot.game_state.world.triggers.disable_trigger(trigger.id)
			break
	var prepared := session.restore(content, snapshot)
	if not _check(prepared.state == SessionStep.State.COMPLETED, "mutated old boundary restores: " + prepared.error_message):
		return null
	return session


func _verify_copy(host: SaveHostController, saves: SaveRepository, old_content: RealmzContent, current: RealmzContent, slot: String, backup: bool) -> void:
	var original := host.load(old_content, slot, backup) as SaveEnvelope
	if not _check(original != null, "source envelope reads"):
		return
	var original_data := original.to_data()
	var copied_slot := host.update_save(current, slot, backup)
	if not _check(not copied_slot.is_empty(), "explicit copy succeeds: " + host.last_error()):
		return
	var expected := original_data.duplicate(true)
	expected["packageHash"] = current.package_hash
	var copied := saves.load(current.campaign_id, copied_slot, current.package_hash)
	_check(copied != null and copied.to_data() == expected, "every field and thumbnail preserved except package identity")
	_check((host.load(old_content, slot, backup) as SaveEnvelope).to_data() == original_data, "original primary or backup remains unchanged")
	_check(host.update_save(current, slot, backup) == copied_slot, "identical retry succeeds")
	var replacement := GameSession.new()
	_check(replacement.restore(current, copied).state == SessionStep.State.COMPLETED, "copied save restores through public session API")
	var pending := replacement.view().pending_interaction
	if pending != null and pending.kind == InteractionRequest.SHOP:
		var resumed := replacement.respond(InteractionResponse.new(pending.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(&"leave")))
		_check(resumed.state != SessionStep.State.FAILED, "copied pending shop resumes")
	copied.game_state.party.fatigue += 1
	_check(saves.save(current.campaign_id, copied_slot, copied, copied.map_preview_jpeg), "prepare different destination data")
	var destination := _save_path(current.campaign_id, copied_slot)
	var collision_hash := FileAccess.get_sha256(destination)
	_check(host.update_save(current, slot, backup).is_empty() and FileAccess.get_sha256(destination) == collision_hash, "conflicting copy is rejected without overwrite")


func _check_pending_shop(host: SaveHostController, saves: SaveRepository, session: GameSession, old_content: RealmzContent, current: RealmzContent) -> void:
	var shop: ShopDefinition
	for native_id: int in range(100):
		shop = old_content.economy.shop_by_classic_id(native_id)
		if shop != null:
			break
	if not _check(shop != null, "representative shop exists"):
		return
	var snapshot := session.snapshot()
	snapshot.game_state.location_services.set_active_shop(shop.id, [0, 0, 0, 0])
	if not _check(session.restore(old_content, snapshot).state == SessionStep.State.COMPLETED, "shop context restores"):
		return
	var opened := session.submit_intent(EconomyIntents.service(shop.id, &"enter"))
	if not _check(opened.state == SessionStep.State.WAITING_FOR_INTERACTION, "ordinary shop opens: " + opened.error_message):
		return
	_check(host.save(old_content, "pending", session.snapshot()), "pending shop writes")
	_verify_copy(host, saves, old_content, current, "pending", false)


func _check_artwork(host: SaveHostController, saves: SaveRepository, session: GameSession, old_content: RealmzContent, current: RealmzContent) -> void:
	var image := Image.create_empty(44, 44, false, Image.FORMAT_RGBA8)
	image.fill(Color("587c93"))
	var png := image.save_png_to_buffer()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(png)
	var id := CharacterArtIdentity.make(CharacterAppearanceDefinition.PORTRAIT, hashing.finish().hex_encode())
	var envelope := SaveEnvelope.from_snapshot(session.snapshot())
	envelope.game_state.party.characters()[0].portrait_id = id
	_check(envelope.character_art.add(id, "Fixture artwork", "Marker test portrait", CharacterAppearanceDefinition.PORTRAIT, png), "portable artwork bundle validates")
	_check(saves.save(old_content.campaign_id, "artwork", envelope), "original save embeds selected artwork")
	_verify_copy(host, saves, old_content, current, "artwork", false)


func _check_failures(repository: PackageRepository, host: SaveHostController, saves: SaveRepository, old_content: RealmzContent, current: RealmzContent, source: String, installed_root: String, scratch: String) -> void:
	var original := host.load(old_content, "A") as SaveEnvelope
	var primary_hash := FileAccess.get_sha256(_save_path(old_content.campaign_id, "A"))
	var backup_hash := FileAccess.get_sha256(_save_path(old_content.campaign_id, "A") + ".bak")
	_check(host.update_save(current, "absent").is_empty() and host.update_save(current, "pending", true).is_empty(), "missing sources and backups reject")
	var unknown := original.to_data().duplicate(true)
	unknown["packageHash"] = "f".repeat(64)
	_check(saves.save(old_content.campaign_id, "unknown", SaveEnvelope.from_data(unknown)), "unlisted save revision writes as scratch fixture")
	_check(host.update_save(current, "unknown").is_empty(), "unlisted save revision cannot update")
	_write_bytes(_save_path(old_content.campaign_id, "corrupt"), "{invalid".to_utf8_buffer())
	var obsolete := original.to_data().duplicate(true)
	obsolete["formatVersion"] = 4
	_write_bytes(_save_path(old_content.campaign_id, "obsolete"), JSON.stringify(obsolete).to_utf8_buffer())
	_check(host.update_save(current, "corrupt").is_empty() and host.update_save(current, "obsolete").is_empty(), "corrupt and obsolete-format saves reject")
	var invalid := original.to_data().duplicate(true)
	invalid.gameState.party.mapId = "missing-map"
	_check(saves.save(old_content.campaign_id, "invalid-state", SaveEnvelope.from_data(invalid)), "invalid-location fixture writes")
	_check(host.update_save(current, "invalid-state").is_empty() and host.last_error().contains("restore"), "invalid replacement state rejects before publication")
	var missing_policy := MarkerSaveUpdate.new(scratch.path_join("missing-packages"))
	_check(not missing_policy.validate_archives(current) and missing_policy.last_error.contains("missing"), "missing original package has actionable failure")
	var write_failure := SaveHostController.new(WriteFailureRepository.new(_save_root), null, null, MarkerSaveUpdate.new(installed_root))
	_check(write_failure.update_save(current, "A", true).is_empty(), "failed copy publication rejects")
	var readback_root := scratch.path_join("readback-failure")
	var readback_saves := ReadbackFailureRepository.new(readback_root)
	_check(readback_saves.save(old_content.campaign_id, "source", original, original.map_preview_jpeg), "readback fixture source writes")
	var readback_failure := SaveHostController.new(readback_saves, null, null, MarkerSaveUpdate.new(installed_root))
	_check(readback_failure.update_save(current, "source").is_empty() and not FileAccess.file_exists(readback_root.path_join(current.campaign_id).path_join(MarkerSaveUpdate.new().updated_slot_id("source", false, current.package_hash) + ".r2save")), "failed readback removes only the unpublished copy")
	var bad_root := scratch.path_join("rejected-packages")
	var installed := repository.install_package(source, bad_root)
	if not _check(installed.is_ok(), "isolated rejection package installs"):
		return
	var path := installed.installed_path
	var receipt_path := path + ".receipt.json"
	var receipt_bytes := FileAccess.get_file_as_bytes(receipt_path)
	var receipt: Dictionary = JSON.parse_string(receipt_bytes.get_string_from_utf8())
	receipt["applicationPackageHash"] = "f".repeat(64)
	_write_bytes(receipt_path, JSON.stringify(receipt).to_utf8_buffer())
	var rejected := MarkerSaveUpdate.new(bad_root)
	_check(not rejected.validate_archives(current) and rejected.last_error.contains("receipt"), "wrong application receipt rejects")
	_write_bytes(receipt_path, "{}".to_utf8_buffer())
	_check(not rejected.validate_archives(current), "malformed receipt rejects")
	_write_bytes(receipt_path, receipt_bytes)
	var archive_bytes := FileAccess.get_file_as_bytes(path)
	_write_bytes(path, archive_bytes + PackedByteArray([0]))
	_check(not rejected.validate_archives(current) and rejected.last_error.contains("archive"), "altered original archive rejects")
	_check_corrected_archive_failure(current, installed_root, scratch)
	_check(FileAccess.get_sha256(_save_path(old_content.campaign_id, "A")) == primary_hash and FileAccess.get_sha256(_save_path(old_content.campaign_id, "A") + ".bak") == backup_hash and host.active_slot(current) == "J", "failures preserve primary, backup and active-slot pointer")
	_check(FileAccess.get_sha256(installed_root.path_join(old_content.campaign_id).path_join(old_content.package_hash + ".realmz2")) == FileAccess.get_sha256(source), "rejection fixtures do not alter the valid original installation")


func _check_corrected_archive_failure(current: RealmzContent, installed_root: String, scratch: String) -> void:
	var entry := MarkerSaveUpdate.new(installed_root).transition(current.campaign_id, current.package_hash)
	var bad_bundle := scratch.path_join("rejected-bundle")
	DirAccess.make_dir_recursive_absolute(bad_bundle)
	var bytes := FileAccess.get_file_as_bytes(MarkerSaveUpdate.BUNDLE_ROOT.path_join(entry.file))
	_write_bytes(bad_bundle.path_join(entry.file), bytes + PackedByteArray([0]))
	_check(not MarkerSaveUpdate.new(installed_root, bad_bundle).validate_archives(current), "altered corrected archive rejects")


func _save_path(campaign: String, slot: String) -> String:
	return _save_root.path_join(campaign).path_join(slot + ".r2save")


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
	return condition
