## Prepares isolated named or checkpoint fixtures through validated public boundaries.
class_name RuntimeTestingFixtureSession
extends RefCounted

var content: RealmzContent
var application_media: MediaSource
var package_media: MediaSource
var identity: Dictionary = {}
var error: Dictionary = {}


func load_request(request: RuntimeTestingFixtureRequest) -> bool:
	if FileAccess.get_sha256(request.package_path).to_lower() != request.package_sha256:
		return _fail("package_hash_mismatch", "The fixture package archive does not match its launch identity.")
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		return _fail(String(application.error_code), application.error_message)
	repository.set_application_content(application.content, application.media.assets())
	var package := repository.load_package(request.package_path)
	if not package.is_ok():
		return _fail(String(package.error_code), package.error_message)
	package.content.characters.install_application_catalog(application.content.characters)
	content = package.content
	application_media = application.media
	package_media = package.media
	identity = {"fixtureId": request.fixture_id, "build": request.build, "engineVersion": Engine.get_version_info()["string"], "applicationPackageHash": ApplicationLibraryIdentity.PACKAGE_HASH, "campaignId": content.campaign_id, "packageHash": content.package_hash, "packageArchiveSha256": request.package_sha256, "sourceKind": request.source["kind"]}
	return true


func start(request: RuntimeTestingFixtureRequest, session: GameSessionController) -> bool:
	if request.source["kind"] == "checkpoint":
		var path: String = request.source["checkpointPath"]
		if FileAccess.get_sha256(path).to_lower() != request.source["checkpointSha256"]:
			return _fail("checkpoint_hash_mismatch", "The clone checkpoint does not match its launch identity.")
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > RuntimeTestingProtocol.MAX_MESSAGE_BYTES:
			return _fail("checkpoint_unavailable", "The clone checkpoint is unavailable or exceeds the protocol bound.")
		var checkpoint := SaveEnvelope.from_data(JSON.parse_string(file.get_as_text()))
		file.close()
		if checkpoint == null:
			return _fail("invalid_checkpoint", "The clone checkpoint failed save-envelope validation.")
		identity["checkpointSha256"] = request.source["checkpointSha256"]
		identity["preparation"] = "validated-checkpoint-restore"
		return _step_ok(session.restore(content, checkpoint))
	return _start_named(request, session)


func _start_named(request: RuntimeTestingFixtureRequest, session: GameSessionController) -> bool:
	if not _step_ok(session.start(content, int(request.source["seed"]))):
		return false
	var catalog := ClassicStarterCharacterCatalog.new()
	var records := catalog.load_records(CharacterVaultController.CLASSIC_STARTER_CATALOG_PATH, ApplicationLibraryIdentity.PACKAGE_HASH)
	if records.is_empty():
		return _fail("starter_catalog_rejected", catalog.last_error)
	var snapshot := session.session().snapshot()
	if snapshot == null:
		return _fail("snapshot_unavailable", "Named fixture preparation could not establish a safe baseline.")
	var rules := RealmzRules.new()
	var characters: Array[Dictionary] = []
	for record: CharacterVaultRecord in records:
		var state := CharacterStateCodec.copy(record.state)
		state.carried_load = rules.inventory.calculated_load(state, content.items.definitions())
		if not snapshot.game_state.party.add_character(state):
			return _fail("starter_state_rejected", "The pinned starter records do not form a uniquely owned party.")
		characters.append({"characterId": record.character_id, "revisionHash": record.revision_hash, "name": record.state.name, "sourceLoad": record.state.carried_load, "derivedLoad": state.carried_load})
	snapshot.game_state.party_setup_completed = true
	snapshot.game_state.scenario_progress.set_quest_value(0, -1)
	if not _step_ok(session.restore(content, snapshot)):
		return false
	var location: Dictionary = request.source["location"]
	if not _step_ok(session.apply_debug_command(SessionDebugCommand.warp(location["mapId"], Vector2i(int(location["x"]), int(location["y"]))))):
		return false
	identity["characters"] = characters
	identity["seed"] = request.source["seed"]
	identity["questZeroSentinel"] = -1
	identity["preparation"] = "validated-starter-snapshot-and-debug-position; derived inventory load; no ordinary import or campaign-start hook"
	return true


func _step_ok(step: SessionStep) -> bool:
	if step == null:
		return _fail("adapter_failure", "Fixture preparation did not return a session step.")
	return _fail(String(step.error_code), step.error_message) if step.state == SessionStep.State.FAILED else true


func _fail(code: String, message: String) -> bool:
	error = {"code": code, "message": message}
	return false
