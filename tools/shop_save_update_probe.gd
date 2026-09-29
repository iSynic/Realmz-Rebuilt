## Isolated package/save proof. Requires retained originals and a new scratch root.
extends SceneTree

var _failures := 0
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or DirAccess.dir_exists_absolute(args[1]):
		printerr("Usage: -- <original-package-directory> <new-scratch-directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not _check(application.is_ok(), "application loads"):
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ShopSaveUpdate.CATALOG_PATH))
	for entry: Dictionary in catalog.transitions:
		_check_campaign(repository, entry, args[0], args[1])
	print("SHOP_SAVE_UPDATE checks=%d failures=%d" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_campaign(repository: PackageRepository, entry: Dictionary, originals: String, scratch: String) -> void:
	var installed_root := scratch.path_join("packages")
	var installed := repository.install_package(originals.path_join(entry.file), installed_root)
	if not _check(installed.is_ok(), "%s original installs: %s" % [entry.campaignId, installed.error_message]):
		return
	var old_content := installed.package.content
	var loaded := repository.load_package(ShopSaveUpdate.BUNDLE_ROOT.path_join(entry.file))
	if not _check(loaded.is_ok(), "corrected package validates: " + loaded.error_message):
		return
	var content := loaded.content
	var session := GameSession.new()
	if not _check(session.start(old_content, 37).state != SessionStep.State.FAILED, "old campaign starts"):
		return
	var view := session.view()
	var spec := CharacterCreationSpec.new("Shop Tester", view.race_options[0].id, view.caste_options[0].id, 1, "", "", 9)
	var created := session.submit_intent(PartyIntents.create([spec]))
	if not _check(created.state != SessionStep.State.FAILED, "party creation: " + created.error_message):
		return
	var snapshot := session.snapshot()
	var old_shop: ShopDefinition
	for native_id: int in range(100):
		var shop := old_content.economy.shop_by_classic_id(native_id)
		if shop != null and not shop.item_ids().is_empty():
			old_shop = shop
			break
	if not _check(old_shop != null, "existing stocked shop exists"):
		return
	snapshot.game_state.location_services.set_shop_quantity(old_shop, 0, 3)
	snapshot.game_state.party.fatigue = 23
	var prepared := session.restore(old_content, snapshot)
	if not _check(prepared.state != SessionStep.State.FAILED, "prepared old save restores: " + prepared.error_message):
		return
	var saves := SaveRepository.new(scratch.path_join("saves"))
	var policy := ShopSaveUpdate.new(installed_root)
	var host := SaveHostController.new(saves, null, policy)
	_check(host.save(old_content, "A", session.snapshot()), "original save writes")
	snapshot = session.snapshot()
	snapshot.game_state.party.fatigue = 24
	session.restore(old_content, snapshot)
	_check(host.save(old_content, "A", session.snapshot()), "second write retains backup")
	_check(host.load(content, "A") == null, "ordinary mismatched load still rejects")
	_check(host.previews(content).any(func(p: SaveSlotPreview) -> bool: return p.slot_id == "A" and p.can_update), "Update Save is offered")
	for backup: bool in [false, true]:
		_verify_copy(host, saves, old_content, content, "A", backup)
	_check(not policy.eligible(content.campaign_id, "f".repeat(64), content.package_hash), "unapproved hash is ineligible")
	var bad_policy := ShopSaveUpdate.new(scratch.path_join("absent"))
	_check(not bad_policy.validate_archives(content), "missing original archive rejects")
	var original_bytes := FileAccess.get_file_as_bytes(installed.installed_path)
	_check(FileAccess.get_sha256(installed.installed_path) == entry.oldArchiveSha256 and not original_bytes.is_empty(), "original archive preserved")
	_test_added_shops(content, session.snapshot(), entry.shopIds)
	_test_pending_shop(host, saves, session, old_content, content, old_shop)
	print("SHOP_SAVE_UPDATE campaign=%s complete" % content.campaign_id)


func _verify_copy(host: SaveHostController, saves: SaveRepository, old_content: RealmzContent, content: RealmzContent, slot: String, backup: bool) -> void:
	var original := host.load(old_content, slot, backup)
	if not _check(original != null, "source save is readable"):
		return
	var original_data := (original as SaveEnvelope).to_data()
	var copy := host.update_save(content, slot, backup)
	if not _check(not copy.is_empty(), "explicit update: " + host.last_error()):
		return
	var updated := saves.load(content.campaign_id, copy, content.package_hash)
	var expected := original_data.duplicate(true)
	expected.packageHash = content.package_hash
	_check(updated != null and updated.to_data() == expected, "only package identity changed; full state and RNG preserved")
	_check((host.load(old_content, slot, backup) as SaveEnvelope).to_data() == original_data, "original primary/backup preserved")
	_check(host.update_save(content, slot, backup) == copy, "identical retry is idempotent")
	var replacement := GameSession.new()
	_check(replacement.restore(content, updated).state != SessionStep.State.FAILED, "updated save restores")
	var pending := replacement.view().pending_interaction
	if pending != null and pending.kind == InteractionRequest.SHOP:
		var resumed := replacement.respond(InteractionResponse.new(pending.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(&"leave")))
		_check(resumed.state != SessionStep.State.FAILED and replacement.view().pending_interaction == null and replacement.snapshot() != null, "updated pending shop resumes and leaves normally")
	updated.game_state.party.fatigue += 1
	_check(saves.save(content.campaign_id, copy, updated), "prepare differing target copy")
	_check(host.update_save(content, slot, backup).is_empty(), "different existing copy is never overwritten")


func _test_pending_shop(host: SaveHostController, saves: SaveRepository, session: GameSession, old_content: RealmzContent, content: RealmzContent, shop: ShopDefinition) -> void:
	var snapshot := session.snapshot()
	snapshot.game_state.location_services.set_active_shop(shop.id, [0, 0, 0, 0])
	if not _check(session.restore(old_content, snapshot).state != SessionStep.State.FAILED, "contextual shop preparation restores"):
		return
	var opened := session.submit_intent(EconomyIntents.service(shop.id, &"enter"))
	if not _check(opened.state != SessionStep.State.FAILED and session.view().pending_interaction != null, "existing shop opens: " + opened.error_message):
		return
	_check(host.save(old_content, "pending", session.snapshot()), "pending shop save writes")
	_verify_copy(host, saves, old_content, content, "pending", false)
	var updated := host.update_save(content, "pending", true)
	_check(updated.is_empty(), "absent source backup cannot be updated")


func _test_added_shops(content: RealmzContent, snapshot: SessionSnapshot, ids: Array) -> void:
	for native_id: int in ids:
		var state := GameState.from_data(snapshot.game_state.to_data())
		var api := RealmzRuntimeApi.new(content, state, RealmzRng.new(7), ScenarioActionState.new(), RealmzRules.new())
		var opened := api.execute_classic(ClassicActionDefinition.new(0, 6, 6, -native_id, false, []), "shop-restoration:%d" % native_id)
		_check(opened.state == ScenarioRuntimeOperationResult.State.WAITING and opened.interaction != null and opened.interaction.kind == InteractionRequest.SHOP and state.location_services.active_shop_id == "classic.shop.%d" % native_id, "negative shop %d opens immediately" % native_id)
		if opened.interaction != null:
			var closed := api.resume_classic(opened.continuation, InteractionResponse.new(opened.interaction.request_id, InteractionRequest.SHOP, InteractionResponse.ShopBody.new(&"leave")), "shop-leave:%d" % native_id)
			_check(closed.state == ScenarioRuntimeOperationResult.State.COMPLETED, "restored shop %d leaves normally" % native_id)


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
	return condition
