class_name RealmzTestCase
extends RefCounted

var assertions: int = 0
var failures: Array[String] = []

const TEST_APPLICATION_LIBRARY_PATH := ApplicationLibraryIdentity.PATH
const TEST_APPLICATION_LIBRARY_ID := ApplicationLibraryIdentity.CAMPAIGN_ID
const TEST_APPLICATION_LIBRARY_HASH := ApplicationLibraryIdentity.PACKAGE_HASH


func _remove_tree(path: String, verified_root: String) -> void:
	if path != verified_root and not path.begins_with(verified_root + "/"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directory.get_directories():
		_remove_tree(path.path_join(directory_name), verified_root)
	DirAccess.remove_absolute(path)


func _restore_fixture_position(session: GameSession, content: RealmzContent, map_id: String, coordinate: Vector2i, assertion_message: String) -> void:
	var envelope := session.snapshot()
	envelope.game_state.party.map_id = map_id
	envelope.game_state.party.coordinate = coordinate
	assert_equal(session.restore(content, envelope).state, SessionStep.State.COMPLETED, assertion_message)


func _aging_race(content: RealmzContent) -> RaceDefinition:
	for race: RaceDefinition in content.characters.race_definitions():
		if race.max_age > 0 and race.age_range(1).x == race.age_range(0).y + 1:
			return race
	return null


func _labels_in(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		if child is Label: labels.append((child as Label).text)
	return labels


func _has_event(step: SessionStep, kind: StringName) -> bool:
	return step.events.any(func(event: DomainEvent) -> bool: return event.kind == kind)


func _fixture_character(character_id: String, display_name: String, content: RealmzContent, maximum_health: int = 12, maximum_load: int = 100, known_spells: Array[String] = []) -> CharacterState:
	var result := CharacterState.new(character_id, display_name, maximum_health, maximum_health)
	result.race_id = content.characters.race_definitions()[0].id
	result.caste_id = content.characters.caste_definitions()[0].id
	if maximum_load >= 0:
		result.maximum_load = maximum_load
	if not known_spells.is_empty():
		result.spellcaster_type = 1
		result.spell_points = 50
		result.maximum_spell_points = 50
		result.set_known_spells(known_spells)
	return result


func _fixture_race_caste_available(content: RealmzContent, assertion_message: String) -> bool:
	var races := content.characters.race_definitions()
	var castes := content.characters.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), assertion_message)
	return not races.is_empty() and not castes.is_empty()


func _begin_standard_fixture_adventure(session: GameSession, content: RealmzContent, party_size: int = 1, number_single_member_name: bool = true) -> void:
	if not _fixture_race_caste_available(content, "fixture content provides playable Race and Caste definitions"):
		return
	for character_index: int in range(clampi(party_size, 1, 6)):
		var member_number := character_index + 1
		var character_id := "fixture.party.member" if party_size == 1 else "fixture.party.member.%d" % member_number
		var display_name := "Fixture Hero %d" % member_number if number_single_member_name or party_size > 1 else "Fixture Hero"
		var character := _fixture_character(character_id, display_name, content, 10, -1)
		var imported := session.submit_intent(PartyIntents.import_vault_character(character.id, "1".repeat(64), character, content.campaign_id, content.package_hash, content.transfer_catalog))
		assert_equal(imported.state, SessionStep.State.COMPLETED, "fixture party import does not consume gameplay RNG")
	var started := session.submit_intent(PartyIntents.begin_adventure())
	if content.scenario.application_hook_program_id(ScenarioApplicationHooks.START_GAME).is_empty():
		assert_equal(started.state, SessionStep.State.COMPLETED, "fixture begins synchronously when Start Game is absent")
	else:
		assert_equal(started.state, SessionStep.State.WAITING_FOR_INTERACTION, "fixture reaches the Start Game hook after party setup")
		assert_equal(session.respond(InteractionResponse.acknowledge(started.interaction)).state, SessionStep.State.COMPLETED, "fixture acknowledges the Start Game hook and enters the adventure")


func _fixture_interaction_payload(request: InteractionRequest, include_ally_selection: bool = true) -> Dictionary:
	if include_ally_selection and request.kind == InteractionRequest.ALLY_SELECTION:
		return {"selectedIds": []}
	if request.kind == InteractionRequest.LEVEL_UP and request.body.to_data().get("mode") == "result":
		return {"action": "continue", "characterId": request.body.to_data()["characterId"]}
	if request.kind == InteractionRequest.LEVEL_UP:
		return {"action": "confirm-spells", "characterId": request.body.to_data()["characterId"], "spellIds": []}
	if request.kind == InteractionRequest.TREASURE_DISTRIBUTION and request.body.to_data().get("mode") == "completion-confirmation":
		return {"action": "confirm-completion"}
	if request.kind == InteractionRequest.TREASURE_DISTRIBUTION and not request.body.to_data().get("items", []).is_empty():
		return {"action": "discard", "instanceId": request.body.to_data()["items"][0]["instanceId"]}
	return {"action": "done"}


func test_package_repository() -> PackageRepository:
	var repository := PackageRepository.new(); var application_library := repository.load_bundled_package(TEST_APPLICATION_LIBRARY_PATH, TEST_APPLICATION_LIBRARY_ID, TEST_APPLICATION_LIBRARY_HASH)
	if application_library.is_ok():
		repository.set_application_content(application_library.content, application_library.media.assets())
	return repository


func load_test_package(path: String) -> PackageLoadResult:
	var repository := test_package_repository()
	var loaded := repository.load_package(path); assert_true(loaded.is_ok(), "shared test package loads through the application-plus-scenario catalog boundary: %s" % loaded.error_message); return loaded


func save_data(snapshot: SessionSnapshot) -> Dictionary:
	var envelope := SaveEnvelope.from_snapshot(snapshot)
	return {} if envelope == null else envelope.to_data()


func save_round_trip(snapshot: SessionSnapshot) -> SaveEnvelope:
	return SaveEnvelope.from_data(save_data(snapshot))


func continuation_data(snapshot: SessionSnapshot) -> Dictionary:
	if snapshot == null or snapshot.continuation == null:
		return {}
	var wire := snapshot.continuation.to_data()
	var payload: Dictionary = wire["data"].duplicate(true)
	payload["kind"] = wire["kind"]
	return payload


func selected_case_arguments() -> Array:
	return []


func assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func assert_false(value: bool, message: String) -> void:
	assert_true(not value, message)


func assert_not_null(value: Variant, message: String) -> void:
	assertions += 1
	if value == null:
		failures.append(message)


func assert_contains(text: String, expected_fragment: String, message: String) -> void:
	assertions += 1
	if not text.contains(expected_fragment):
		failures.append("%s (expected '%s' in '%s')" % [message, expected_fragment, text])
