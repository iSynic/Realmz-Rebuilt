extends RealmzTestCase

const CharacterCreationSessionScript := preload("res://src/session/character_creation_session.gd")
const CLASSIC_CHARACTER_LIBRARY_PATH: String = "res://src/infrastructure/characters/realmz-classic-character-library.realmz2"
const CLASSIC_CHARACTER_LIBRARY_ID: String = "realmz-classic-character-library"
const CLASSIC_CHARACTER_LIBRARY_HASH: String = "6e3f23c9a452f70b25040c729e17533de5ddf0c420ff35484fc52f6e0dd25e68"


func run() -> void:
	var loaded := PackageRepository.new().load_bundled_package(CLASSIC_CHARACTER_LIBRARY_PATH, CLASSIC_CHARACTER_LIBRARY_ID, CLASSIC_CHARACTER_LIBRARY_HASH)
	assert_true(loaded.is_ok(), "the standalone creator test uses the pinned Providence-built stock catalog: %s" % loaded.error_message)
	if not loaded.is_ok():
		return
	var creator: RefCounted = CharacterCreationSessionScript.new()
	assert_equal(creator.start(loaded.content, 7920, "realmz.character.1").state, SessionStep.State.COMPLETED, "the application-owned creator starts without a selected scenario")
	var view: GameView = creator.view()
	assert_true(view.party_setup_available and view.party_members.is_empty(), "the stock workshop reuses the typed five-step creator view without assembling a campaign party")
	assert_true([view.race_options.size(), view.caste_options.size(), view.portrait_options.size(), view.combat_icon_options.size()] == [30, 30, 120, 120] and not view.race_options[0].facts.is_empty() and not view.caste_options[0].facts.is_empty(), "the workshop exposes the complete stock creation catalog with detached source-backed Race and Caste facts")
	var human := loaded.content.race_by_id("classic.race.1")
	var fighter := loaded.content.caste_by_id("classic.caste.1")
	var portrait := loaded.content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT)[0]
	var icon := loaded.content.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON)[0]
	var spec := CharacterCreationSpec.new("Standalone", human.id, fighter.id, 1, portrait.id, icon.id, 1)
	var generated: SessionStep = creator.submit_intent(PlayerIntent.generate_character_draft(spec))
	assert_equal(generated.state, SessionStep.State.COMPLETED, "a stock Race and Class generate through the same source-backed GameSession transaction")
	assert_equal([creator.view().character_draft.name, creator.view().character_draft.race_name, creator.view().character_draft.caste_name], ["Standalone", "Human", "Fighter"], "the reviewed draft uses stock definitions and names")
	var finalized: SessionStep = creator.submit_intent(PlayerIntent.finalize_character())
	assert_equal(finalized.state, SessionStep.State.COMPLETED, "standalone finalization accepts the vault publication boundary implicitly")
	assert_true(finalized.events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_publication_requested"), "standalone completion still crosses the one typed host publication event")
	var completed: CharacterState = creator.completed_character()
	assert_not_null(completed, "the host can detach the completed character for transactional publication")
	if completed != null:
		assert_equal(completed.id, "realmz.character.1", "the host-owned stable Character File identity replaces the workshop party identity")
		assert_true(not completed.inventory().is_empty(), "standalone publication retains the ordinary Classic starting inventory transaction")
	assert_equal(creator.publication_committed().state, SessionStep.State.COMPLETED, "the host can acknowledge a successful vault write")
	var unsupported: RefCounted = CharacterCreationSessionScript.new()
	assert_equal(unsupported.start(loaded.content, 15839, "realmz.character.2").state, SessionStep.State.COMPLETED, "a second workshop starts independently")
	assert_equal(unsupported.submit_intent(PlayerIntent.create_party([spec])).error_code, &"unsupported_character_intent", "the standalone creator cannot begin an adventure or broaden into campaign ownership")
