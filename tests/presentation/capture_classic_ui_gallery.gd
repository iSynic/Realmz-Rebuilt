extends SceneTree

const FIXTURE_PATH := "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const OUTPUT_ROOT := "res://artifacts/ui-gallery"

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
	var gallery_view := _application.session_controller.view()
	if not gallery_view.party_members.is_empty():
		var definition := _application._active_content.item_by_id("classic.item.901")
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
	_interaction.present(ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION))
	await _settle()
	await _capture("wide-encounter-1280x720")
	_interaction.present(null)
	var gallery_names: Array[String] = ["Ari", "Bryn", "Corin", "Dara", "Elian", "Fara"]
	while gallery_view.party_members.size() < 6 and not gallery_view.party_members.is_empty():
		var member_index := gallery_view.party_members.size()
		var member_state := CharacterState.new("gallery-member-%d" % member_index, gallery_names[member_index], 8 + member_index, 10 + member_index)
		member_state.race_id = gallery_view.party_members[0].race_id
		member_state.caste_id = gallery_view.party_members[0].caste_id
		member_state.armor = member_index
		gallery_view.party_members.append(CharacterView.new(member_state, _application._active_content))
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
	_router.open_screen(&"combat")
	await _settle()
	await _capture("wide-combat-unavailable-1920x1080")
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
