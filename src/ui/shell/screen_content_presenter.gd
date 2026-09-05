## Routes detached game views into the controller responsible for each mounted screen.
class_name ScreenContentPresenter
extends RefCounted

const CREATURE_LIBRARY_CONTROLLER := preload("res://src/ui/characters/creature_library_screen_controller.gd")

signal intent_submitted(intent: PlayerIntent)
signal system_action_requested(action_id: StringName, value: Variant)
signal presentation_setting_changed(setting_id: StringName, value: Variant)
signal vault_archive_requested(character_id: String)
signal vault_restore_requested(character_id: String, revision_hash: String)
signal route_requested(screen_id: StringName)
signal refresh_requested
signal back_requested
signal sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool)

const MUTED := Color("9aa0a8")
const SWAP_OPEN_SOUND_ID: int = 3003
const SWAP_DONE_SOUND_ID: int = 141

var _view: GameView
var _settings: PresentationSettings = PresentationSettings.new()
var _media: ClassicMediaCatalog
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _ordinary_money_workspace_open: bool = false
var _system_controller := SystemScreenController.new()
var _character_controller := CharacterScreenController.new()
var _inventory_controller := InventoryScreenController.new()
var _services_controller := ServicesScreenController.new()
var _maps_journal_controller := MapsJournalScreenController.new()
var _spells_controller := SpellsScreenController.new()
var _creature_library_controller := CREATURE_LIBRARY_CONTROLLER.new()
var _message_label_scene_path := "res://src/ui/shared/screen_message_label.tscn"
var _summary_card_scene_path := "res://src/ui/shared/screen_summary_card.tscn"


func set_component_scene_paths(message_label_path: String, summary_card_path: String) -> void:
	_message_label_scene_path = message_label_path
	_summary_card_scene_path = summary_card_path


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id
	_character_controller.set_layout_profile(profile_id)
	_creature_library_controller.set_layout_profile(profile_id)
	_inventory_controller.set_layout_profile(profile_id)
	_maps_journal_controller.set_layout_profile(profile_id)
	_services_controller.set_layout_profile(profile_id)
	_system_controller.set_layout_profile(profile_id)
	_spells_controller.set_layout_profile(profile_id)


func _init() -> void:
	var owner_ref: WeakRef = weakref(self)
	_bind_system_controller(owner_ref)
	_bind_character_controller(owner_ref)
	_bind_inventory_controller(owner_ref)
	_bind_services_controller(owner_ref)
	_bind_maps_and_spells_controllers(owner_ref)


func _bind_system_controller(owner_ref: WeakRef) -> void:
	_system_controller.action_requested.connect(func(action_id: StringName, value: Variant) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.system_action_requested.emit(action_id, value)
	)
	_system_controller.setting_changed.connect(func(setting_id: StringName, value: Variant) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.presentation_setting_changed.emit(setting_id, value)
	)


func _bind_character_controller(owner_ref: WeakRef) -> void:
	_character_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.intent_submitted.emit(intent)
	)
	_character_controller.refresh_requested.connect(func() -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.refresh_requested.emit()
	)
	_character_controller.vault_back_requested.connect(func() -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.back_requested.emit()
	)
	_character_controller.vault_archive_requested.connect(func(character_id: String) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.vault_archive_requested.emit(character_id)
	)
	_character_controller.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.vault_restore_requested.emit(character_id, revision_hash)
	)


func _bind_inventory_controller(owner_ref: WeakRef) -> void:
	_inventory_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.intent_submitted.emit(intent)
	)
	_inventory_controller.refresh_requested.connect(func() -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.refresh_requested.emit()
	)
	_inventory_controller.route_requested.connect(func(screen_id: StringName) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.route_requested.emit(screen_id)
	)
	_inventory_controller.back_requested.connect(func() -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.back_requested.emit()
	)


func _bind_services_controller(owner_ref: WeakRef) -> void:
	_services_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.intent_submitted.emit(intent)
	)
	_services_controller.route_requested.connect(func(screen_id: StringName) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.route_requested.emit(screen_id)
	)
	_services_controller.refresh_requested.connect(func() -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.refresh_requested.emit()
	)


func _bind_maps_and_spells_controllers(owner_ref: WeakRef) -> void:
	_maps_journal_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.intent_submitted.emit(intent)
	)
	_spells_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.intent_submitted.emit(intent)
	)
	_spells_controller.route_requested.connect(func(screen_id: StringName) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.route_requested.emit(screen_id)
	)
	_spells_controller.sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool) -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.sound_requested.emit(sound_id, wait_for_completion, stop_existing, false)
	)
	_spells_controller.refresh_requested.connect(func() -> void:
		var owner := owner_ref.get_ref() as ScreenContentPresenter
		if owner != null:
			owner.refresh_requested.emit()
	)


func set_view(view: GameView) -> void:
	_view = view


func reset_campaign() -> void:
	_character_controller.reset()
	_inventory_controller.reset()
	_spells_controller.reset()
	_creature_library_controller.reset()


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	_character_controller.set_vault_revisions(revisions)


func set_save_previews(previews: Array[SaveSlotPreview]) -> void:
	_system_controller.set_save_previews(previews)


func set_save_and_quit_mode(enabled: bool) -> void:
	_system_controller.set_save_and_quit_mode(enabled)


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media


func set_presentation_settings(settings: PresentationSettings) -> void:
	if settings != null:
		_settings = settings


func clear_vault_inspection() -> void:
	_character_controller.clear_vault_inspection()


func handle_vault_back() -> bool:
	return _character_controller.handle_vault_back()


func party_order_draft_ids() -> Array[String]:
	return _character_controller.draft_order_ids()


func select_inventory_character(character_id: String) -> bool:
	return _inventory_controller.select_roster_character(character_id, _view)


func select_character(character_id: String) -> bool:
	return _character_controller.select_character(character_id, _view)


func sync_route_audio(screen_id: StringName) -> void:
	var service_interaction_open := _view != null and _view.pending_interaction != null and _view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK]
	var should_be_open := screen_id == &"services" and _view != null and _view.session_started and not service_interaction_open
	if should_be_open == _ordinary_money_workspace_open:
		return
	_ordinary_money_workspace_open = should_be_open
	if should_be_open:
		sound_requested.emit(SWAP_DONE_SOUND_ID, false, false, false)
		sound_requested.emit(SWAP_OPEN_SOUND_ID, false, true, true)
	else:
		sound_requested.emit(SWAP_DONE_SOUND_ID, false, false, false)


func present(screen_id: StringName, screen: ScreenFrame, appearance_textures: Dictionary, vault_back_label: String, context_actions: Container = null) -> void:
	if screen == null:
		return
	var body := screen.body_control()
	if screen_id not in [&"allies", &"bestiary", &"character", &"inventory", &"journal", &"services", &"spells", &"system", &"vault"]:
		_clear(body)
	if context_actions != null:
		_clear(context_actions)
	if (_view == null or not _view.session_started) and screen_id != &"vault":
		var message_host: Container = body
		if screen is CharacterScreen:
			var character_screen := screen as CharacterScreen
			character_screen.prepare_for_render()
			message_host = character_screen.character_sheet_area()
		elif screen is CreatureLibraryScreen:
			var creature_screen := screen as CreatureLibraryScreen
			creature_screen.prepare_for_render(_layout_profile == UiLayoutProfile.COMPACT)
			message_host = creature_screen.detail_panel()
		elif screen is InventoryScreen:
			message_host = (screen as InventoryScreen).prepare_alternate_layout()
		elif screen is JournalScreen:
			message_host = (screen as JournalScreen).prepare_alternate_layout()
		elif screen is ServicesScreen:
			message_host = (screen as ServicesScreen).prepare_alternate_layout()
		elif screen is SpellsScreen:
			message_host = (screen as SpellsScreen).prepare_alternate_layout()
		elif screen is SystemScreen:
			message_host = (screen as SystemScreen).prepare_alternate_layout()
		_add_label(message_host, "No active session. Choose a validated campaign to begin.", MUTED)
		return
	match screen_id:
		&"exploration":
			_add_card(body, "Exploration", "The map presenter occupies the central Classic viewport. Use the command rail and textbox overlay for player-facing actions.", "Day %d • %02d:%02d" % [_view.realmz_day, _view.realmz_hour, _view.realmz_minute])
		&"character":
			_character_controller.present(screen as CharacterScreen, _view, appearance_textures, _settings, _media)
		&"allies":
			_creature_library_controller.present_allies(screen, _view, _media, _settings.text_scale)
		&"bestiary":
			_creature_library_controller.present_bestiary(screen, _view, _media, _settings.text_scale)
		&"vault":
			_character_controller.present_vault(screen, _view, appearance_textures, _settings.text_scale, vault_back_label, _media)
		&"inventory":
			_inventory_controller.present(screen as InventoryScreen, _view, _media, _settings.text_scale)
		&"spells":
			_spells_controller.present(screen, _view, _media, _settings.text_scale, context_actions)
		&"services":
			_services_controller.set_text_scale(_settings.text_scale)
			_services_controller.present(screen, _view, _media)
		&"journal":
			_maps_journal_controller.set_text_scale(_settings.text_scale)
			_maps_journal_controller.present(screen, _view, _media)
		&"system":
			_system_controller.present(screen, _view, _settings)


func _add_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var panel := (load(_summary_card_scene_path) as PackedScene).instantiate() as PanelContainer
	var title_label := panel.get_node("SummaryContent/SummaryTitle") as Label
	var subtitle_label := panel.get_node("SummaryContent/SummarySubtitle") as Label
	var detail_label := panel.get_node("SummaryContent/SummaryDetail") as Label
	title_label.text = title
	subtitle_label.text = subtitle
	detail_label.text = detail
	detail_label.visible = not detail.is_empty()
	for label: Label in [title_label, subtitle_label, detail_label]:
		label.add_theme_font_size_override("font_size", int(round(float(label.get_theme_font_size("font_size")) * _settings.text_scale)))
	parent.add_child(panel)


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := (load(_message_label_scene_path) as PackedScene).instantiate() as Label
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _settings.text_scale)))
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
