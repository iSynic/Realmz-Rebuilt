class_name ClassicScreenRouter
extends Control

signal screen_changed(screen_id: StringName)
signal route_exiting(screen_id: StringName)
signal workspace_focus_restored(screen_id: StringName, focus_key: String)
signal start_requested(package_path: String, seed: int)
signal cancel_package_requested
signal refresh_requested
signal intent_submitted(intent: PlayerIntent)
signal system_action_requested(action_id: StringName, value: Variant)
signal presentation_setting_changed(setting_id: StringName, value: Variant)
signal vault_archive_requested(character_id: String)
signal vault_restore_requested(character_id: String, revision_hash: String)
signal presentation_sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool)
signal standalone_character_creation_requested
signal standalone_character_creation_cancelled

const MUTED := Color("9aa0a8")
const ERROR := Color("ef7770")
const SWAP_OPEN_SOUND_ID: int = 3003
const SWAP_DONE_SOUND_ID: int = 141
var _view: GameView
var _screen_id: StringName = &"exploration"
var _body_scroll: ScrollContainer
var _body: VBoxContainer
var _body_frame: PanelContainer
var _workspace_view: ClassicRouteScreen
var _settings: PresentationSettings = PresentationSettings.new()
var _media: ClassicMediaCatalog
var _route_history: Array[StringName] = []
var _route_transition_revision: int = 0
var _focus_keys: Dictionary = {}
var _workspace_rect := Rect2(220.0, 100.0, 512.0, 430.0)
var _layout_profile: StringName = UiLayoutProfile.STANDARD
var _modal_layout_rect := Rect2(12.0, 36.0, 680.0, 556.0)
var _campaign_layout_rect := Rect2(12.0, 36.0, 228.0, 556.0)
var _setup_layout_rect := Rect2(12.0, 36.0, 936.0, 556.0)
var _content_parent: Container
var _character_sheet_character_id: String = ""
var _character_sheet_tab: StringName = &"overview"
var _presented_campaign_id: String = ""
var _vault_return_to_setup: bool = false
var _vault_return_to_campaign: bool = false
var _vault_return_to_splash: bool = false
var _ordinary_money_workspace_open: bool = false
var _system_controller := SystemWorkspaceController.new()
var _character_controller := CharacterWorkspaceController.new()
var _inventory_controller := InventoryWorkspaceController.new()
var _services_controller := ServicesWorkspaceController.new()
var _maps_journal_controller := MapsJournalWorkspaceController.new()
var _spells_controller := SpellsWorkspaceController.new()
var setup_controller := CampaignPartySetupController.new()
var _initialized: bool = false


func _init() -> void:
	setup_controller.attach(self)
	setup_controller.start_requested.connect(func(package_path: String, seed: int) -> void: start_requested.emit(package_path, seed))
	setup_controller.cancel_package_requested.connect(func() -> void: cancel_package_requested.emit())
	setup_controller.refresh_requested.connect(func() -> void: refresh_requested.emit())
	setup_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	setup_controller.standalone_character_creation_requested.connect(func() -> void: standalone_character_creation_requested.emit())
	setup_controller.standalone_character_creation_cancelled.connect(func() -> void: standalone_character_creation_cancelled.emit())
	setup_controller.campaign_selection_requested.connect(show_campaign_selection)
	setup_controller.vault_requested.connect(_show_vault_from_splash)
	setup_controller.quit_requested.connect(func() -> void: system_action_requested.emit(&"quit", null))
	_system_controller.action_requested.connect(func(action_id: StringName, value: Variant) -> void: system_action_requested.emit(action_id, value))
	_system_controller.setting_changed.connect(func(setting_id: StringName, value: Variant) -> void: presentation_setting_changed.emit(setting_id, value))
	_character_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_character_controller.refresh_requested.connect(func() -> void: _render_screen())
	_character_controller.vault_back_requested.connect(func() -> void: handle_back())
	_character_controller.vault_archive_requested.connect(func(character_id: String) -> void: vault_archive_requested.emit(character_id))
	_character_controller.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: vault_restore_requested.emit(character_id, revision_hash))
	_inventory_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_inventory_controller.refresh_requested.connect(func() -> void: _render_screen())
	_services_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_services_controller.route_requested.connect(func(screen_id: StringName) -> void: open_screen(screen_id))
	_maps_journal_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_spells_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_spells_controller.route_requested.connect(func(screen_id: StringName) -> void: open_screen(screen_id))
	_spells_controller.sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool) -> void: presentation_sound_requested.emit(sound_id, wait_for_completion, stop_existing))


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The router spans the window for layout only. Its panels and workspace own
	# input; the router itself must not cover menus or other shell controls.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_body()
	setup_controller.build_splash_overlay()
	setup_controller.build_campaign_overlay()
	setup_controller.build_setup_overlay()
	show_splash()


func present(view: GameView) -> void:
	var completed_party_setup := _party_setup_completed(_view, view)
	_view = view
	if view == null or not view.session_started:
		_body_frame.visible = false
		return
	if not _presented_campaign_id.is_empty() and _presented_campaign_id != view.campaign_id:
		setup_controller.reset_creator(true)
		_character_controller.reset()
		_inventory_controller.reset()
		_character_sheet_character_id = ""
		_character_sheet_tab = &"overview"
	_presented_campaign_id = view.campaign_id
	setup_controller.present(view)
	if view.party_setup_available:
		if setup_controller.splash_overlay != null:
			setup_controller.splash_overlay.visible = false
		setup_controller.campaign_overlay.visible = true
		setup_controller.setup_overlay.visible = true
		_body_frame.visible = false
		call_deferred("_apply_modal_layouts")
		call_deferred("_focus_first", setup_controller.setup_overlay)
		return
	if completed_party_setup:
		_finish_party_setup_navigation()
	setup_controller.setup_overlay.visible = false
	if setup_controller.splash_overlay != null:
		setup_controller.splash_overlay.visible = false
	setup_controller.campaign_overlay.visible = false
	_render_screen()


static func _party_setup_completed(previous_view: GameView, next_view: GameView) -> bool:
	return previous_view != null and previous_view.party_setup_available and next_view != null and next_view.session_started and not next_view.party_setup_available


func _finish_party_setup_navigation() -> void:
	_vault_return_to_setup = false
	_vault_return_to_campaign = false
	_character_controller.clear_vault_inspection()
	setup_controller.finish_party_setup_navigation()
	_route_history.clear()
	if _screen_id == &"exploration":
		return
	_screen_id = &"exploration"
	_sync_ordinary_money_workspace_audio(_screen_id)
	screen_changed.emit(_screen_id)


func set_campaigns(campaigns: Array[CampaignPackageView]) -> void:
	setup_controller.set_campaigns(campaigns)


func set_package_operation(status: RefCounted) -> void:
	setup_controller.set_package_operation(status)


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	_character_controller.set_vault_revisions(revisions)
	setup_controller.set_vault_revisions(revisions)
	if _screen_id == &"vault":
		_render_screen()
	elif setup_controller.setup_overlay != null and setup_controller.setup_overlay.visible:
		setup_controller.refresh_setup_options()


func set_standalone_character_creation_available(enabled: bool, reason: String = "") -> void:
	setup_controller.set_standalone_character_creation_available(enabled, reason)


func begin_standalone_character_creation() -> void:
	setup_controller.begin_standalone_character_creation()


func finish_standalone_character_creation() -> void:
	setup_controller.finish_standalone_character_creation()


func present_party_setup_status(text: String, is_error: bool = false) -> void:
	setup_controller.present_party_setup_status(text, is_error)


func set_save_previews(previews: Array[SaveSlotPreview]) -> void:
	_system_controller.set_save_previews(previews)
	if _screen_id == &"system" and _view != null and _view.session_started:
		_render_screen()


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	setup_controller.set_media_catalog(media)
	if _view != null and _view.session_started:
		_render_screen()


func set_presentation_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_settings = settings
	setup_controller.set_presentation_settings(settings)
	if _screen_id == &"system":
		_render_screen()


func set_layout_profile(profile: UiLayoutProfile, viewport_size: Vector2) -> void:
	if profile == null:
		return
	_layout_profile = profile.id
	var top := profile.menu_height
	var bottom := profile.bottom_height
	_workspace_rect = Rect2(0.0, top, maxf(320.0, viewport_size.x - profile.party_width), maxf(220.0, viewport_size.y - top - bottom))
	_modal_layout_rect = Rect2(12.0, top + 8.0, maxf(320.0, viewport_size.x - 24.0), maxf(300.0, viewport_size.y - top - 16.0))
	_campaign_layout_rect = ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
	_setup_layout_rect = _modal_layout_rect
	if setup_controller.setup_overlay != null:
		setup_controller.apply_layout(profile, _campaign_layout_rect, _setup_layout_rect)
	_apply_modal_layouts()
	_render_screen()


static func campaign_rect_for(profile: UiLayoutProfile, viewport_size: Vector2) -> Rect2:
	var modal_rect := Rect2(12.0, profile.menu_height + 8.0, maxf(320.0, viewport_size.x - 24.0), maxf(300.0, viewport_size.y - profile.menu_height - 16.0))
	var campaign_width := clampf(228.0 * profile.ui_scale, 200.0, minf(268.0, modal_rect.size.x * 0.32))
	return Rect2(modal_rect.position, Vector2(campaign_width, modal_rect.size.y))


func _apply_modal_layouts() -> void:
	if _workspace_view != null:
		_workspace_view.set_workspace_rect(_workspace_layout_rect())
	setup_controller.apply_modal_layouts()


func _refresh_campaign_layout() -> void:
	_apply_modal_layouts()
	if setup_controller.campaign_scroll != null:
		setup_controller.campaign_scroll.scroll_vertical = 0


func _prepare_campaign_selection() -> void:
	_refresh_campaign_layout()
	setup_controller._focus_first(setup_controller.setup_overlay)
	if setup_controller.campaign_scroll != null:
		setup_controller.campaign_scroll.scroll_vertical = 0


func show_splash() -> void:
	if setup_controller.splash_overlay == null:
		return
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	setup_controller.show_splash()
	_body_frame.visible = false


func show_campaign_selection() -> void:
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	setup_controller.show_campaign_selection()
	_body_frame.visible = false
	call_deferred("_prepare_campaign_selection")


func full_stage_overlay_visible() -> bool:
	return setup_controller.full_stage_overlay_visible() or _screen_id == &"vault"


func accepts_exploration_input() -> bool:
	return not setup_controller.full_stage_overlay_visible() and _screen_id == &"exploration"


func open_screen(screen_id: StringName) -> void:
	if not UiRouteCatalog.has_route(screen_id):
		return
	if screen_id == &"vault":
		_vault_return_to_campaign = false
		_vault_return_to_setup = false
	_store_focus()
	if screen_id != _screen_id:
		route_exiting.emit(_screen_id)
		_route_history.append(_screen_id)
	_screen_id = screen_id
	setup_controller.hide_overlays()
	_sync_ordinary_money_workspace_audio(screen_id)
	_render_screen(true)


func handle_back() -> bool:
	if setup_controller.handle_back():
		return true
	if _screen_id == &"vault" and _character_controller.handle_vault_back():
		return true
	if _screen_id == &"vault" and _vault_return_to_setup and _view != null and _view.party_setup_available:
		_vault_return_to_setup = false
		_screen_id = &"exploration"
		setup_controller.show_party_setup()
		_body_frame.visible = false
		return true
	if _screen_id == &"vault" and _vault_return_to_campaign:
		show_campaign_selection()
		return true
	if _screen_id == &"vault" and _vault_return_to_splash:
		show_splash()
		return true
	if setup_controller.campaign_overlay.visible:
		if _view != null and _view.party_setup_available:
			show_splash()
			return true
		if _view != null and _view.session_started:
			setup_controller.hide_overlays()
			_render_screen()
			return true
		show_splash()
		return true
	if setup_controller.splash_visible():
		return false
	if setup_controller.setup_overlay.visible:
		return false
	if not _route_history.is_empty():
		var previous: StringName = _route_history.pop_back()
		route_exiting.emit(_screen_id)
		_screen_id = previous
		_sync_ordinary_money_workspace_audio(previous)
		_render_screen(true)
		return true
	if _screen_id != &"exploration":
		route_exiting.emit(_screen_id)
		_screen_id = &"exploration"
		_sync_ordinary_money_workspace_audio(_screen_id)
		_render_screen(true)
		return true
	return false


func _sync_ordinary_money_workspace_audio(screen_id: StringName) -> void:
	var service_interaction_open := _view != null and _view.pending_interaction != null and _view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK]
	var should_be_open := screen_id == &"services" and _view != null and _view.session_started and not service_interaction_open
	if should_be_open == _ordinary_money_workspace_open:
		return
	_ordinary_money_workspace_open = should_be_open
	if should_be_open:
		presentation_sound_requested.emit(SWAP_DONE_SOUND_ID, false, false)
		presentation_sound_requested.emit(SWAP_OPEN_SOUND_ID, false, true)
	else:
		presentation_sound_requested.emit(SWAP_DONE_SOUND_ID, false, false)


func current_screen() -> StringName:
	return _screen_id


func primary_workspace_id() -> StringName:
	return _workspace_view.route_id if _workspace_view != null else &""


func mounted_primary_workspace_count() -> int:
	var count := 0
	for child: Node in get_children():
		if child is ClassicRouteScreen:
			count += 1
	return count


func primary_workspace_visible() -> bool:
	return _workspace_view != null and _workspace_view.visible


func party_order_draft_ids() -> Array[String]:
	return _character_controller.draft_order_ids()


func _build_body() -> void:
	_mount_workspace(_screen_id)


func _workspace_layout_rect() -> Rect2:
	return _modal_layout_rect if _screen_id == &"vault" else _workspace_rect


func _mount_workspace(screen_id: StringName) -> void:
	if _workspace_view != null and _workspace_view.route_id == screen_id:
		return
	if _workspace_view != null:
		remove_child(_workspace_view)
		_workspace_view.queue_free()
	var definition := UiRouteCatalog.route(screen_id)
	var scene := load(String(definition.get("scene", ""))) as PackedScene
	if scene == null:
		push_error("Missing Classic route scene for %s" % screen_id)
		return
	_workspace_view = scene.instantiate() as ClassicRouteScreen
	_workspace_view.name = "WorkspaceFrame"
	add_child(_workspace_view)
	move_child(_workspace_view, 0)
	_workspace_view.set_workspace_rect(_workspace_layout_rect())
	_body_frame = _workspace_view
	_body_scroll = _workspace_view.scroll_control()
	_body = _workspace_view.body_control()




func _render_screen(notify_route_change: bool = false) -> void:
	var mounted_new_route := _workspace_view == null or _workspace_view.route_id != _screen_id
	var previous_scroll_horizontal := _body_scroll.scroll_horizontal if _body_scroll != null else 0
	var previous_scroll_vertical := _body_scroll.scroll_vertical if _body_scroll != null else 0
	_mount_workspace(_screen_id)
	if notify_route_change:
		screen_changed.emit(_screen_id)
	if _workspace_view != null:
		_workspace_view.set_workspace_rect(_workspace_layout_rect())
	if _body == null:
		return
	_route_transition_revision += 1
	var transition_revision := _route_transition_revision
	_clear(_body)
	_content_parent = _body
	_body_frame.visible = not setup_controller.full_stage_overlay_visible() and _screen_id not in [&"exploration", &"combat"]
	if _screen_id in [&"exploration", &"combat"]:
		call_deferred("_complete_route_render", transition_revision, false, previous_scroll_horizontal, previous_scroll_vertical)
		return
	if (_view == null or not _view.session_started) and _screen_id != &"vault":
		_add_label(_body, "No active session. Choose a validated campaign to begin.", MUTED)
		call_deferred("_complete_route_render", transition_revision, mounted_new_route, previous_scroll_horizontal, previous_scroll_vertical)
		return
	match _screen_id:
		&"exploration":
			_add_card("Exploration", "The map presenter occupies the central Classic viewport. Use the command rail and textbox overlay for player-facing actions.", "Day %d • %02d:%02d" % [_view.realmz_day, _view.realmz_hour, _view.realmz_minute])
		&"character":
			_render_characters()
		&"vault":
			_render_vault()
		&"inventory":
			_render_inventory()
		&"spells":
			_render_spells()
		&"services":
			_render_services()
		&"journal":
			_render_journal()
		&"system":
			_render_system()
	_assign_focus_keys(_body)
	call_deferred("_complete_route_render", transition_revision, mounted_new_route, previous_scroll_horizontal, previous_scroll_vertical)


func _complete_route_render(transition_revision: int, reset_scroll_to_top: bool, previous_scroll_horizontal: int, previous_scroll_vertical: int) -> void:
	if transition_revision != _route_transition_revision:
		return
	_restore_focus(reset_scroll_to_top, previous_scroll_horizontal, previous_scroll_vertical)
	var viewport := get_viewport()
	if viewport == null:
		workspace_focus_restored.emit(_screen_id, "")
		return
	var focus_owner := viewport.gui_get_focus_owner()
	var focus_key := String(focus_owner.get_meta("focus_key", "")) if focus_owner != null and is_ancestor_of(focus_owner) else ""
	workspace_focus_restored.emit(_screen_id, focus_key)


func _render_characters() -> void:
	setup_controller.ensure_appearance_textures()
	_character_controller.present(_body, _view, setup_controller.appearance_textures(), _settings)


func _render_vault() -> void:
	setup_controller.ensure_appearance_textures()
	var back_label := "Back to party setup" if _vault_return_to_setup else "Back to campaigns" if _vault_return_to_campaign else "Back"
	_character_controller.present_vault(_body, _view, setup_controller.appearance_textures(), _settings.text_scale, back_label)


func _show_vault_from_campaign() -> void:
	_vault_return_to_campaign = true
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	setup_controller.hide_overlays()
	_screen_id = &"vault"
	_body_frame.visible = true
	screen_changed.emit(_screen_id)
	_render_screen()


func _show_vault_from_splash() -> void:
	_vault_return_to_splash = true
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	setup_controller.hide_overlays()
	_screen_id = &"vault"
	_body_frame.visible = true
	screen_changed.emit(_screen_id)
	_render_screen()


func _render_inventory() -> void:
	_inventory_controller.present(_body, _view, _media, _settings.text_scale)


func _render_spells() -> void:
	_spells_controller.present(_body, _view, _media, _settings.text_scale)


func _render_services() -> void:
	_services_controller.set_text_scale(_settings.text_scale)
	_services_controller.present(_body, _view)


func _render_journal() -> void:
	_maps_journal_controller.set_text_scale(_settings.text_scale)
	_maps_journal_controller.present(_body, _view, _media)


func _render_system() -> void:
	_system_controller.present(_body, _view, _settings)


func _add_card(title: String, subtitle: String, detail: String) -> void:
	_add_card_to(_content_parent, title, subtitle, detail)


func _add_card_to(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size.x = 280.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_add_label(box, title, Color("e7d078"), 17)
	_add_label(box, subtitle, Color("e0e2e5"))
	if not detail.is_empty():
		_add_label(box, detail, MUTED)
	parent.add_child(panel)


func _assign_focus_keys(parent: Node, next_index: int = 0) -> int:
	for child: Node in parent.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			if not child.has_meta("focus_key"):
				child.set_meta("focus_key", "%s:%d" % [_screen_id, next_index])
			next_index += 1
		next_index = _assign_focus_keys(child, next_index)
	return next_index


func _store_focus() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var owner := viewport.gui_get_focus_owner()
	if owner != null and is_ancestor_of(owner) and owner.has_meta("focus_key"):
		_focus_keys[_screen_id] = String(owner.get_meta("focus_key"))


func _restore_focus(reset_scroll_to_top: bool = false, previous_scroll_horizontal: int = 0, previous_scroll_vertical: int = 0) -> void:
	var wanted := String(_focus_keys.get(_screen_id, ""))
	var restored := false
	if not wanted.is_empty():
		var focus_match := _find_focus_key(_body, wanted)
		if focus_match != null:
			focus_match.grab_focus()
			restored = true
	if not restored:
		_focus_first(_body)
	if _body_scroll != null:
		# Focus restoration runs before the rebuilt layout has settled and can
		# otherwise force the ScrollContainer to its final focusable control.
		_body_scroll.scroll_horizontal = 0 if reset_scroll_to_top else previous_scroll_horizontal
		_body_scroll.scroll_vertical = 0 if reset_scroll_to_top else previous_scroll_vertical


func _find_focus_key(parent: Node, key: String) -> Control:
	for child: Node in parent.get_children():
		if child is Control and child.has_meta("focus_key") and String(child.get_meta("focus_key")) == key:
			return child
		var nested := _find_focus_key(child, key)
		if nested != null:
			return nested
	return null


func _focus_first(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.is_inside_tree() and control.visible and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return
		_focus_first(child)
		var viewport := get_viewport()
		var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
		if focus_owner != null and parent.is_ancestor_of(focus_owner):
			return


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * _settings.text_scale)))
	return label


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
