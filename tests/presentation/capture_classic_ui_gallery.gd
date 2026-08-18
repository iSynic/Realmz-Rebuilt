extends SceneTree

const FIXTURE_PATH := "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const OUTPUT_ROOT := "res://artifacts/ui-gallery"
const CHARACTER_VIEW_SCRIPT := preload("res://src/core/view/character_view.gd")

var _application: RealmzApplication
var _shell: ClassicApplicationShell
var _router: ClassicScreenRouter
var _interaction: InteractionPresenter


func _initialize() -> void:
	call_deferred("_capture_gallery")


func _capture_gallery() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_ROOT))
	_application = load("res://src/presentation/realmz_application.tscn").instantiate() as RealmzApplication
	root.add_child(_application)
	_shell = _application.get_node("ClassicShell") as ClassicApplicationShell
	_router = _shell.get_node("ScreenRouter") as ClassicScreenRouter
	_interaction = _application.get_node("InteractionPanel") as InteractionPresenter
	await _settle()
	await _resize(Vector2i(800, 600))
	await _capture("compact-campaign-800x600")
	await _resize(Vector2i(1280, 720))
	Input.warp_mouse(Vector2(520, 18))
	await _settle()
	await _capture("canonical-campaign-menu-hover-1280x720")
	await _resize(Vector2i(800, 600))
	_application.start_package(FIXTURE_PATH, 1)
	await _settle()
	await _capture("compact-party-setup-800x600")
	var setup_view := _application.session_controller.view()
	var setup := _router.setup_controller
	setup.create_character_button.pressed.emit()
	await _settle()
	await _capture("compact-character-creator-identity-800x600")
	await _resize(Vector2i(1280, 720))
	setup.selected_race_id = setup_view.race_options[0].id
	setup.selected_caste_id = setup_view.caste_options[0].id
	setup.creator_step = 2
	setup.render_creator_step()
	await _settle()
	await _capture("canonical-character-creator-appearance-1280x720")
	setup.reset_creator(true)
	await _settle()
	var member := CharacterCreationSpec.new("Ari", setup_view.race_options[0].id, setup_view.caste_options[0].id, 1)
	_application.session_controller.submit_intent(PlayerIntent.create_party([member]))
	await _settle()
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"exploration")
	await _settle()
	await _capture("canonical-explore-1280x720")
	_interaction.present(InteractionRequest.acknowledge("gallery-edge-to-edge", "The party follows the old road toward Northgate."))
	await _settle()
	await _capture("canonical-acknowledge-edge-to-edge-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-acknowledge-800x600")
	await _resize(Vector2i(1280, 720))
	_interaction.present(null)
	var gallery_view: Variant = _application.session_controller.view()
	if not gallery_view.party_members.is_empty():
		var active_content: Variant = _application.get("_active_content")
		var definition: Variant = active_content.item_by_id("classic.item.901")
		if definition != null:
			for index: int in 18:
				gallery_view.party_members[0].items.append(ItemView.new(ItemInstance.new("gallery-item-%d" % index, definition.id, maxi(1, definition.initial_charges), false, index % 3 != 0), definition))
	_shell.present(gallery_view)
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"inventory")
	await _settle()
	await _capture("wide-dense-inventory-1280x720")
	_router.open_screen(&"spells")
	await _settle()
	await _capture("wide-spells-1280x720")
	_router.open_screen(&"journal")
	await _settle()
	await _capture("wide-journal-1280x720")
	_router.open_screen(&"exploration")
	await _settle()
	_interaction.present(InteractionRequest.from_payload("gallery-classic-choice", InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No"}), "Will you enter the ruined keep?")
	await _settle()
	await _capture("wide-classic-choice-context-1280x720")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION))
	await _settle()
	await _capture("wide-encounter-1280x720")
	await _resize(Vector2i(800, 600))
	await _capture("classic-encounter-800x600")
	await _resize(Vector2i(1280, 720))
	for interaction_kind: StringName in [
		InteractionRequest.AGE_UPDATE,
		InteractionRequest.INDEXED_CHOICE,
		InteractionRequest.ENCOUNTER_CHOICE,
		InteractionRequest.CHARACTER_SELECTION,
		InteractionRequest.ALLY_SELECTION,
		InteractionRequest.TEMPLE,
		InteractionRequest.BANK,
		InteractionRequest.POOLED_WEALTH_DEPARTURE,
		InteractionRequest.SESSION_LIFECYCLE,
	]:
		_interaction.present(ClassicUiFixtureGallery.request_for(interaction_kind))
		await _settle()
		await _capture("wide-interaction-%s-1280x720" % String(interaction_kind).replace("_", "-"))
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION))
	await _resize(Vector2i(800, 600))
	await _settle()
	await _capture("classic-treasure-distribution-800x600")
	await _resize(Vector2i(1280, 720))
	await _settle()
	await _capture("wide-treasure-distribution-1280x720")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"missing_media"))
	await _settle()
	await _capture("wide-fumble-recovery-1280x720")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP))
	await _settle()
	await _capture("wide-level-result-1280x720")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.LEVEL_UP, &"unidentified"))
	await _settle()
	await _capture("wide-level-spells-1280x720")
	_interaction.present(null)
	var gallery_names: Array[String] = ["Ari", "Bryn", "Corin", "Dara", "Elian", "Fara"]
	while gallery_view.party_members.size() < 6 and not gallery_view.party_members.is_empty():
		var member_index: int = int(gallery_view.party_members.size())
		var member_state := CharacterState.new("gallery-member-%d" % member_index, gallery_names[member_index], 8 + member_index, 10 + member_index)
		member_state.race_id = gallery_view.party_members[0].race_id
		member_state.caste_id = gallery_view.party_members[0].caste_id
		member_state.armor = member_index
		gallery_view.party_members.append(CHARACTER_VIEW_SCRIPT.new(member_state, _application.get("_active_content")))
	_shell.present(gallery_view)
	_router.open_screen(&"character")
	await _settle()
	await _capture("canonical-character-record-1280x720")
	_router.open_screen(&"allies")
	await _settle()
	await _capture("canonical-allies-empty-1280x720")
	if not gallery_view.party_members.is_empty():
		var vault_revision := CharacterVaultRevisionView.new()
		vault_revision.character_id = gallery_view.party_members[0].id
		vault_revision.revision_hash = "a".repeat(64)
		vault_revision.name = gallery_view.party_members[0].name
		vault_revision.level = gallery_view.party_members[0].level
		vault_revision.race_id = gallery_view.party_members[0].race_id
		vault_revision.caste_id = gallery_view.party_members[0].caste_id
		vault_revision.portrait_id = gallery_view.party_members[0].portrait_id
		vault_revision.is_current = true
		vault_revision.eligible = true
		vault_revision.character = gallery_view.party_members[0]
		_router.set_vault_revisions([vault_revision])
		_router.open_screen(&"vault")
		await _settle()
		await _capture("canonical-character-files-1280x720")
	await _resize(Vector2i(800, 600))
	_router.open_screen(&"exploration")
	await _settle()
	await _capture("classic-six-member-roster-800x600")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.SHOP))
	await _resize(Vector2i(800, 600))
	await _settle()
	await _capture("classic-shop-interaction-800x600")
	await _resize(Vector2i(1280, 720))
	await _settle()
	await _capture("canonical-shop-interaction-1280x720")
	_interaction.present(null)
	var service := ServiceView.new()
	service.service_id = "gallery-shop"
	service.service_kind = &"shop"
	service.title = "Provisioner"
	service.actions = [&"buy", &"sell", &"identify", &"leave"]
	service.disabled_reasons[&"identify"] = "This shop does not identify items."
	gallery_view.services.clear()
	gallery_view.services.append(service)
	_shell.present(gallery_view)
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"services")
	await _settle()
	await _capture("canonical-services-1280x720")
	var combat_fixture := _combat_view(gallery_view)
	gallery_view.combat_view = combat_fixture
	_router.open_screen(&"combat")
	_application._battlefield_presenter.present(gallery_view)
	_application._battlefield_presenter.visible = true
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT))
	await _settle()
	await _capture("canonical-combat-tactical-workspace-1280x720")
	await _resize(Vector2i(800, 600))
	await _settle()
	await _capture("classic-combat-tactical-workspace-800x600")
	var spells_button := _interaction.find_child("CombatCommandSpells", true, false) as Button
	if spells_button != null and not spells_button.disabled:
		spells_button.pressed.emit()
		await _settle()
		await _capture("classic-combat-spellbook-800x600")
		await _resize(Vector2i(1280, 720))
		await _capture("canonical-combat-spellbook-1280x720")
	_interaction.present(null)
	gallery_view.combat_view = null
	await _resize(Vector2i(1280, 720))
	_router.open_screen(&"system")
	await _settle()
	await _capture("canonical-system-1280x720")
	var settings := PresentationSettings.new()
	settings.text_scale = 1.5
	settings.ui_scale_mode = PresentationSettings.UI_SCALE_150
	_shell.apply_settings(settings)
	await _resize(Vector2i(800, 600))
	_router.open_screen(&"system")
	await _settle()
	await _capture("compact-system-ui150-text150-800x600")
	_application.queue_free()
	await process_frame
	quit(0)


func _resize(size: Vector2i) -> void:
	root.size = size
	DisplayServer.window_set_size(size)
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _capture(label: String) -> void:
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUTPUT_ROOT, label]
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		printerr("Unable to save UI gallery frame %s: %s" % [label, error_string(error)])
	else:
		print("CAPTURED: %s" % path)


func _combat_view(game_view: Variant) -> CombatView:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(232)
	for y: int in range(38, 53):
		for x: int in range(36, 55):
			tiles[y * BattlefieldState.SIZE + x] = 1 + posmod(x * 7 + y * 11, 200)
	var battlefield := BattlefieldState.new("land:0", tiles)
	var hero_view: Variant = game_view.party_members[0]
	var hero := CharacterState.new(hero_view.id, hero_view.name, hero_view.current_health, hero_view.maximum_health)
	hero.combat_icon_id = hero_view.combat_icon_id
	hero.movement = 8
	hero.maximum_movement = 10
	battlefield.place_character(hero.id, Vector2i(45, 45))
	var monster := MonsterState.new("gallery.goblin", "classic.monster.1", "Goblin Raider", 8, 10)
	monster.icon_id = 9001
	battlefield.place_monster(monster.id, Vector2i(47, 45), 0)
	var combat := CombatState.new("classic.battle.gallery", [monster], 0, battlefield)
	combat.set_turn_order([hero.id, monster.id])
	var result := CombatView.new(combat, [hero], _application.get("_active_content"))
	result.attack_units_remaining = 2
	result.movement_remaining = 8
	result.legal_actions = [&"defend", &"finish"]
	result.targets = [MonsterView.new(monster)]
	result.movement_options = [
		CombatMoveOptionView.new(Vector2i(-1, -1), BattlefieldStepResult.permitted(Vector2i(44, 44), 1)),
		CombatMoveOptionView.new(Vector2i.UP, BattlefieldStepResult.permitted(Vector2i(45, 44), 1)),
		CombatMoveOptionView.new(Vector2i(1, -1), BattlefieldStepResult.permitted(Vector2i(46, 44), 1)),
		CombatMoveOptionView.new(Vector2i.LEFT, BattlefieldStepResult.permitted(Vector2i(44, 45), 1)),
		CombatMoveOptionView.new(Vector2i.RIGHT, BattlefieldStepResult.blocked(&"occupied", Vector2i(46, 45), monster.id), false, false, monster.id, monster.name),
		CombatMoveOptionView.new(Vector2i(-1, 1), BattlefieldStepResult.permitted(Vector2i(44, 46), 2)),
		CombatMoveOptionView.new(Vector2i.DOWN, BattlefieldStepResult.permitted(Vector2i(45, 46), 1)),
		CombatMoveOptionView.new(Vector2i.ONE, BattlefieldStepResult.permitted(Vector2i(46, 46), 2)),
	]
	return result
