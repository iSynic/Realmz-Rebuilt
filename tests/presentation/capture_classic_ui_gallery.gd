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
	await _resize(Vector2i(960, 600))
	Input.warp_mouse(Vector2(520, 18))
	await _settle()
	await _capture("standard-campaign-menu-hover-960x600")
	await _resize(Vector2i(800, 600))
	_application.start_package(FIXTURE_PATH, 1)
	await _settle()
	await _capture("compact-party-setup-800x600")
	var setup_view := _application.session_controller.view()
	var member := CharacterCreationSpec.new("Ari", setup_view.race_options[0].id, setup_view.caste_options[0].id, 1)
	_application.session_controller.submit_intent(PlayerIntent.create_party([member]))
	await _settle()
	await _resize(Vector2i(960, 600))
	_router.open_screen(&"exploration")
	await _settle()
	await _capture("standard-explore-960x600")
	_interaction.present(InteractionRequest.acknowledge("gallery-edge-to-edge", "The party follows the old road toward Northgate."))
	await _settle()
	await _capture("standard-acknowledge-edge-to-edge-960x600")
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
	_interaction.present(InteractionRequest.new("gallery-classic-choice", InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No"}), "Will you enter the ruined keep?")
	await _settle()
	await _capture("wide-classic-choice-context-1280x720")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION))
	await _settle()
	await _capture("wide-encounter-1280x720")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION))
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
	await _resize(Vector2i(960, 600))
	_router.open_screen(&"exploration")
	await _settle()
	await _capture("standard-six-member-roster-960x600")
	await _resize(Vector2i(1600, 900))
	_router.open_screen(&"exploration")
	await _settle()
	await _capture("wide-explore-original-controls-2x-1600x900")
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.SHOP))
	await _settle()
	await _capture("wide-shop-interaction-1600x900")
	_interaction.present(null)
	var service := ServiceView.new()
	service.service_id = "gallery-shop"
	service.service_kind = &"shop"
	service.title = "Provisioner"
	service.actions = [&"buy", &"sell", &"identify", &"leave"]
	service.disabled_reasons[&"identify"] = "This shop does not identify items."
	gallery_view.services = [service]
	_shell.present(gallery_view)
	await _resize(Vector2i(1920, 1080))
	_router.open_screen(&"services")
	await _settle()
	await _capture("wide-services-1920x1080")
	var combat_fixture := _combat_view(gallery_view)
	gallery_view.combat_view = combat_fixture
	_router.open_screen(&"combat")
	_application._battlefield_presenter.present(gallery_view)
	_application._battlefield_presenter.visible = true
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.COMBAT))
	await _settle()
	await _capture("wide-combat-tactical-workspace-1920x1080")
	await _resize(Vector2i(960, 600))
	await _settle()
	await _capture("standard-combat-tactical-workspace-960x600")
	_interaction.present(null)
	gallery_view.combat_view = null
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
