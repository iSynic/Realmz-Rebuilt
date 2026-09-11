extends RealmzTestCase

const CharacterCreationSessionScript := preload("res://src/playthrough/characters/character_creation_session.gd")
const CLASSIC_CHARACTER_LIBRARY_PATH: String = ApplicationLibraryIdentity.PATH
const CLASSIC_CHARACTER_LIBRARY_ID: String = ApplicationLibraryIdentity.CAMPAIGN_ID
const CLASSIC_CHARACTER_LIBRARY_HASH: String = ApplicationLibraryIdentity.PACKAGE_HASH


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
	var human := loaded.content.characters.race_by_id("classic.race.1")
	var fighter := loaded.content.characters.caste_by_id("classic.caste.1")
	var portrait := loaded.content.characters.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT)[0]
	var icon := loaded.content.characters.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON)[0]
	var spec := CharacterCreationSpec.new("Standalone", human.id, fighter.id, 1, portrait.id, icon.id, 1)
	var generated: SessionStep = creator.submit_intent(PartyIntents.generate_character_draft(spec))
	assert_equal(generated.state, SessionStep.State.COMPLETED, "a stock Race and Class generate through the same source-backed GameSession transaction")
	assert_equal([creator.view().character_draft.name, creator.view().character_draft.race_name, creator.view().character_draft.caste_name], ["Standalone", "Human", "Fighter"], "the reviewed draft uses stock definitions and names")
	var finalized: SessionStep = creator.submit_intent(PartyIntents.finalize_character())
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
	assert_equal(unsupported.submit_intent(PartyIntents.create([spec])).error_code, &"unsupported_character_intent", "the standalone creator cannot begin an adventure or broaden into campaign ownership")
