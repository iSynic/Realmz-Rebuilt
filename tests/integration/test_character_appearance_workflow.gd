extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var package_result := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(package_result.is_ok(), "the synthetic package loads before active appearance testing")
	if not package_result.is_ok():
		return
	var content := package_result.content
	var portraits := content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT)
	var icons := content.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON)
	assert_equal([portraits.size(), icons.size()], [120, 120], "Providence supplies both complete Classic appearance catalogs")
	if portraits.size() < 2 or icons.size() < 2:
		return

	var session := GameSession.new()
	assert_equal(session.start(content, 41).state, SessionStep.State.COMPLETED, "appearance testing starts from a deterministic session")
	var setup := session.view()
	var race := setup.race_options[0]
	var caste_id := race.related_ids[0] if not race.related_ids.is_empty() else setup.caste_options[0].id
	assert_equal(session.submit_intent(PlayerIntent.create_party([CharacterCreationSpec.new("Mira", race.id, caste_id, 1)])).state, SessionStep.State.COMPLETED, "the fixture party begins the adventure")
	var character_id := session.view().party_members[0].id
	var initial_character := session.snapshot().game_state.party.character_by_id(character_id)
	var initial_portrait := initial_character.portrait_id
	var initial_icon := initial_character.combat_icon_id
	var target_portrait: CharacterAppearanceDefinition = portraits[1] if portraits[0].id == initial_portrait else portraits[0]
	var target_icon: CharacterAppearanceDefinition = icons[1] if icons[0].id == initial_icon else icons[0]
	assert_true(session.view().availability(&"change_character_appearance").enabled, "the active noncombat party exposes appearance editing")
	assert_equal([session.view().portrait_options.size(), session.view().combat_icon_options.size()], [120, 120], "the detached active-session view exposes the complete package catalogs")

	var state_before := save_data(session.snapshot())
	var rng_before := session.snapshot().rng_state.to_data()
	var portrait_change := session.submit_intent(PlayerIntent.change_character_appearance(character_id, CharacterAppearanceDefinition.PORTRAIT, target_portrait.id))
	assert_equal(portrait_change.state, SessionStep.State.COMPLETED, "a valid portrait change commits synchronously")
	assert_equal(portrait_change.events.size(), 1, "the portrait change emits one committed domain event")
	assert_equal([portrait_change.events[0].kind, portrait_change.events[0].payload["appearanceKind"], portrait_change.events[0].payload["previousAppearanceId"], portrait_change.events[0].payload["appearanceId"]], [&"character_appearance_changed", "portrait", initial_portrait, target_portrait.id], "the portrait event records exact previous and current stable IDs")
	var after_portrait := session.snapshot().game_state.party.character_by_id(character_id)
	assert_equal([after_portrait.portrait_id, after_portrait.combat_icon_id], [target_portrait.id, initial_icon], "changing the portrait does not silently pair or replace the tactical icon")
	assert_equal(session.snapshot().rng_state.to_data(), rng_before, "appearance changes consume no gameplay randomness")
	assert_equal(session.snapshot().game_state.clock.to_data(), state_before["gameState"]["clock"], "appearance changes advance no game time")

	var icon_change := session.submit_intent(PlayerIntent.change_character_appearance(character_id, CharacterAppearanceDefinition.COMBAT_ICON, target_icon.id))
	assert_equal(icon_change.state, SessionStep.State.COMPLETED, "a valid combat-icon change commits independently")
	var after_icon := session.snapshot().game_state.party.character_by_id(character_id)
	assert_equal([after_icon.portrait_id, after_icon.combat_icon_id], [target_portrait.id, target_icon.id], "the two active appearance roles remain independent")

	var committed := save_data(session.snapshot())
	var wrong_role := session.submit_intent(PlayerIntent.change_character_appearance(character_id, CharacterAppearanceDefinition.PORTRAIT, target_icon.id))
	assert_equal([wrong_role.state, wrong_role.error_code], [SessionStep.State.FAILED, &"invalid_character_appearance"], "a tactical icon cannot be assigned as a portrait")
	assert_equal(save_data(session.snapshot()), committed, "wrong-role rejection is transactional")
	var unknown_member := session.submit_intent(PlayerIntent.change_character_appearance("character.unknown", CharacterAppearanceDefinition.PORTRAIT, target_portrait.id))
	assert_equal([unknown_member.state, unknown_member.error_code], [SessionStep.State.FAILED, &"unknown_party_member"], "an unknown character cannot receive an appearance")
	assert_equal(save_data(session.snapshot()), committed, "unknown-character rejection is transactional")
	var unchanged := session.submit_intent(PlayerIntent.change_character_appearance(character_id, CharacterAppearanceDefinition.COMBAT_ICON, target_icon.id))
	assert_equal([unchanged.state, unchanged.error_code], [SessionStep.State.FAILED, &"appearance_unchanged"], "an unchanged selection does not fabricate a mutation")
	assert_equal(save_data(session.snapshot()), committed, "unchanged rejection is transactional")

	var restored := GameSession.new()
	var envelope := SaveEnvelope.from_data(committed)
	assert_not_null(envelope, "the changed appearance has a canonical save envelope")
	assert_equal(restored.restore(content, envelope).state, SessionStep.State.COMPLETED, "the changed portrait and icon restore transactionally")
	var restored_character := restored.view().party_members[0]
	assert_equal([restored_character.portrait_id, restored_character.combat_icon_id], [target_portrait.id, target_icon.id], "save/restore preserves both exact package identities")

	var tampered_data := committed.duplicate(true)
	tampered_data["gameState"]["party"]["characters"][0]["portraitId"] = target_icon.id
	var tampered := SaveEnvelope.from_data(tampered_data)
	assert_not_null(tampered, "wire parsing alone accepts a structurally valid but wrong-role appearance for package validation")
	var replacement_before := save_data(restored.snapshot())
	var rejected_restore := restored.restore(content, tampered)
	assert_equal([rejected_restore.state, rejected_restore.error_code], [SessionStep.State.FAILED, &"invalid_game_state"], "restore rejects a saved tactical icon in the portrait role")
	assert_equal(save_data(restored.snapshot()), replacement_before, "failed appearance restore leaves the active session untouched")
	var empty_identity_data := committed.duplicate(true)
	empty_identity_data["gameState"]["party"]["characters"][0]["portraitId"] = ""
	empty_identity_data["gameState"]["party"]["characters"][0]["combatIconId"] = ""
	var empty_identity := SaveEnvelope.from_data(empty_identity_data)
	var empty_restored := GameSession.new()
	assert_equal(empty_restored.restore(content, empty_identity).state, SessionStep.State.COMPLETED, "an explicit no-appearance save remains valid without substituting package art")
	assert_equal([empty_restored.view().party_members[0].portrait_id, empty_restored.view().party_members[0].combat_icon_id], ["", ""], "restore preserves the explicit unavailable-media state")
