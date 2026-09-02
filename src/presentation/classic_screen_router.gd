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
signal presentation_sound_requested(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool)
signal standalone_character_creation_requested
signal standalone_character_creation_cancelled

const CLASSIC_WORKSPACE_PRESENTER := preload("res://src/presentation/controllers/classic_workspace_presenter.gd")
const WORKSPACE_OPEN_SOUND_IDS: Dictionary = {
	&"inventory": 20001,
	&"spells": 20002,
}

var _view: GameView
var _screen_id: StringName = &"exploration"
var _body_scroll: ScrollContainer
var _body: VBoxContainer
var _body_frame: PanelContainer
var _workspace_view: ClassicRouteScreen
var _route_history: Array[StringName] = []
var _route_transition_revision: int = 0
var _focus_keys: Dictionary = {}
var _workspace_rect := Rect2(220.0, 100.0, 512.0, 430.0)
var _spell_workspace_rect := Rect2(928.0, 28.0, 352.0, 502.0)
var _full_height_workspace_rect := Rect2(0.0, 28.0, 992.0, 692.0)
var _application_workspace_rect := Rect2(0.0, 28.0, 1280.0, 692.0)
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _modal_layout_rect := Rect2(12.0, 36.0, 680.0, 556.0)
var _campaign_layout_rect := Rect2(12.0, 36.0, 228.0, 556.0)
var _setup_layout_rect := Rect2(12.0, 36.0, 936.0, 556.0)
var _presented_campaign_id: String = ""
var _vault_return_to_setup: bool = false
var _vault_return_to_campaign: bool = false
var _vault_return_to_splash: bool = false
var _load_after_campaign_selection: bool = false
var _system_return_to_setup: bool = false
var _workspace_host: Control
var _overlay_host: Control
var _media: ClassicMediaCatalog
var _workspace_presenter := CLASSIC_WORKSPACE_PRESENTER.new()
var setup_controller := CampaignPartySetupController.new()
var _initialized: bool = false
var _startup_splash_enabled: bool = true


func _init() -> void:
	setup_controller.start_requested.connect(func(package_path: String, seed: int) -> void: start_requested.emit(package_path, seed))
	setup_controller.cancel_package_requested.connect(func() -> void: cancel_package_requested.emit())
	setup_controller.refresh_requested.connect(func() -> void: refresh_requested.emit())
	setup_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	setup_controller.standalone_character_creation_requested.connect(func() -> void: standalone_character_creation_requested.emit())
	setup_controller.standalone_character_creation_cancelled.connect(func() -> void: standalone_character_creation_cancelled.emit())
	setup_controller.campaign_selection_requested.connect(func() -> void: show_campaign_selection())
	setup_controller.load_adventure_requested.connect(func() -> void: show_campaign_selection(true))
	setup_controller.load_saved_adventure_requested.connect(_show_load_workspace)
	setup_controller.vault_requested.connect(show_vault_from_splash)
	setup_controller.quit_requested.connect(func() -> void: system_action_requested.emit(&"quit", null))
	_workspace_presenter.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	_workspace_presenter.system_action_requested.connect(func(action_id: StringName, value: Variant) -> void: system_action_requested.emit(action_id, value))
	_workspace_presenter.presentation_setting_changed.connect(func(setting_id: StringName, value: Variant) -> void: presentation_setting_changed.emit(setting_id, value))
	_workspace_presenter.vault_archive_requested.connect(func(character_id: String) -> void: vault_archive_requested.emit(character_id))
	_workspace_presenter.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: vault_restore_requested.emit(character_id, revision_hash))
	_workspace_presenter.route_requested.connect(func(screen_id: StringName) -> void: open_screen(screen_id))
	_workspace_presenter.refresh_requested.connect(func() -> void: _render_screen())
	_workspace_presenter.back_requested.connect(func() -> void: handle_back())
	_workspace_presenter.sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool) -> void: presentation_sound_requested.emit(sound_id, wait_for_completion, stop_existing, reduced_sound_eligible))


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
	_ensure_hosts()
	setup_controller.attach(_overlay_host)
	_build_body()
	setup_controller.build_splash_overlay()
	setup_controller.build_campaign_overlay()
	setup_controller.build_setup_overlay()
	if _startup_splash_enabled:
		show_splash()
	else:
		setup_controller.hide_overlays()
		_body_frame.visible = false


func set_startup_splash_enabled(enabled: bool) -> void:
	_startup_splash_enabled = enabled


func _ensure_hosts() -> void:
	_workspace_host = get_node_or_null("WorkspaceHost") as Control
	if _workspace_host == null:
		_workspace_host = Control.new()
		_workspace_host.name = "WorkspaceHost"
		_workspace_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_workspace_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_workspace_host)
	_overlay_host = get_node_or_null("OverlayHost") as Control
	if _overlay_host == null:
		_overlay_host = Control.new()
		_overlay_host.name = "OverlayHost"
		_overlay_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_overlay_host)


func present(view: GameView) -> void:
	var completed_party_setup := _party_setup_completed(_view, view)
	_view = view
	_workspace_presenter.set_view(view)
	if view == null or not view.session_started:
		setup_controller.present(view)
		_body_frame.visible = false
		return
	if not _presented_campaign_id.is_empty() and _presented_campaign_id != view.campaign_id:
		setup_controller.reset_creator(true)
		_workspace_presenter.reset_campaign()
	_presented_campaign_id = view.campaign_id
	setup_controller.present(view)
	if view.party_setup_available:
		if _load_after_campaign_selection:
			_load_after_campaign_selection = false
			_show_load_workspace()
			return
		if _system_return_to_setup and _screen_id == &"system":
			setup_controller.hide_overlays()
			_render_screen()
			return
		setup_controller.show_party_setup()
		_body_frame.visible = false
		call_deferred("_apply_modal_layouts")
		call_deferred("_focus_first", setup_controller.setup_overlay)
		return
	if completed_party_setup:
		_finish_party_setup_navigation()
	setup_controller.hide_overlays()
	_render_screen()


static func _party_setup_completed(previous_view: GameView, next_view: GameView) -> bool:
	return previous_view != null and previous_view.party_setup_available and next_view != null and next_view.session_started and not next_view.party_setup_available


func _finish_party_setup_navigation() -> void:
	_vault_return_to_setup = false
	_vault_return_to_campaign = false
	_load_after_campaign_selection = false
	_system_return_to_setup = false
	_workspace_presenter.clear_vault_inspection()
	setup_controller.finish_party_setup_navigation()
	_route_history.clear()
	if _screen_id == &"exploration":
		return
	_screen_id = &"exploration"
	_workspace_presenter.sync_route_audio(_screen_id)
	screen_changed.emit(_screen_id)


func set_campaigns(campaigns: Array[CampaignPackageView]) -> void:
	setup_controller.set_campaigns(campaigns)


func set_package_operation(status: RefCounted) -> void:
	setup_controller.set_package_operation(status)


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	_workspace_presenter.set_vault_revisions(revisions)
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
	_workspace_presenter.set_save_previews(previews)
	if _screen_id == &"system" and _view != null and _view.session_started:
		_render_screen()


func set_save_and_quit_mode(enabled: bool) -> void:
	_workspace_presenter.set_save_and_quit_mode(enabled)
	if _screen_id == &"system" and _view != null and _view.session_started:
		_render_screen()


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	if _media == media:
		return
	_media = media
	_workspace_presenter.set_media_catalog(media)
	setup_controller.set_media_catalog(media)
	if _view != null and _view.session_started:
		_render_screen()


func set_presentation_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	_workspace_presenter.set_presentation_settings(settings)
	setup_controller.set_presentation_settings(settings)
	if _screen_id == &"system":
		_render_screen()


func set_layout_profile(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2 = Vector2.ZERO) -> void:
	if profile == null:
		return
	_layout_profile = profile.id
	_workspace_presenter.set_layout_profile(profile.id)
	var top := profile.menu_height
	var bottom := profile.bottom_height
	_workspace_rect = Rect2(origin + Vector2(0.0, top), Vector2(maxf(320.0, viewport_size.x - profile.party_width), maxf(220.0, viewport_size.y - top - bottom)))
	_spell_workspace_rect = spell_workspace_rect_for(profile, viewport_size, origin)
	_full_height_workspace_rect = Rect2(origin + Vector2(0.0, top), Vector2(maxf(320.0, viewport_size.x - profile.party_width), maxf(220.0, viewport_size.y - top)))
	_application_workspace_rect = Rect2(origin + Vector2(0.0, top), Vector2(maxf(320.0, viewport_size.x), maxf(220.0, viewport_size.y - top)))
	_modal_layout_rect = Rect2(origin + Vector2(12.0, top + 8.0), Vector2(maxf(320.0, viewport_size.x - 24.0), maxf(300.0, viewport_size.y - top - 16.0)))
	_campaign_layout_rect = ClassicScreenRouter.campaign_rect_for(profile, viewport_size, origin)
	_setup_layout_rect = _modal_layout_rect
	if setup_controller.setup_overlay != null:
		setup_controller.apply_layout(profile, _campaign_layout_rect, _setup_layout_rect)
	_apply_modal_layouts()
	_render_screen()


static func campaign_rect_for(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2 = Vector2.ZERO) -> Rect2:
	var modal_rect := Rect2(origin + Vector2(12.0, profile.menu_height + 8.0), Vector2(maxf(320.0, viewport_size.x - 24.0), maxf(300.0, viewport_size.y - profile.menu_height - 16.0)))
	var campaign_width := clampf(228.0 * profile.ui_scale, 200.0, minf(268.0, modal_rect.size.x * 0.32))
	return Rect2(modal_rect.position, Vector2(campaign_width, modal_rect.size.y))


static func spell_workspace_rect_for(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2 = Vector2.ZERO) -> Rect2:
	var desired_width := (288.0 if profile.id == UiLayoutProfile.COMPACT else 420.0) * profile.ui_scale
	var minimum_stage_width := 480.0 * profile.ui_scale
	var workspace_width := minf(desired_width, maxf(profile.party_width, viewport_size.x - minimum_stage_width))
	return Rect2(origin + Vector2(viewport_size.x - workspace_width, profile.menu_height), Vector2(workspace_width, maxf(220.0, viewport_size.y - profile.menu_height)))


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
	setup_controller.focus_first(setup_controller.setup_overlay)
	if setup_controller.campaign_scroll != null:
		setup_controller.campaign_scroll.scroll_vertical = 0


func show_splash() -> void:
	if setup_controller.splash_overlay == null:
		return
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	_load_after_campaign_selection = false
	_system_return_to_setup = false
	setup_controller.show_splash()
	_body_frame.visible = false


func show_campaign_selection(load_after_selection: bool = false) -> void:
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	_load_after_campaign_selection = load_after_selection
	_system_return_to_setup = false
	setup_controller.show_campaign_selection()
	_body_frame.visible = false
	call_deferred("_prepare_campaign_selection")


func full_stage_overlay_visible() -> bool:
	return setup_controller.full_stage_overlay_visible() or _screen_id == &"vault"


func accepts_exploration_input() -> bool:
	return not setup_controller.full_stage_overlay_visible() and _screen_id == &"exploration"


func open_screen(screen_id: StringName, play_opening_sound: bool = true) -> void:
	if not UiRouteCatalog.has_route(screen_id):
		return
	if screen_id == &"vault":
		_vault_return_to_campaign = false
		_vault_return_to_setup = false
	_store_focus()
	var changed := screen_id != _screen_id
	if changed:
		route_exiting.emit(_screen_id)
		_route_history.append(_screen_id)
	_screen_id = screen_id
	setup_controller.hide_overlays()
	_workspace_presenter.sync_route_audio(screen_id)
	if changed and play_opening_sound and WORKSPACE_OPEN_SOUND_IDS.has(screen_id):
		presentation_sound_requested.emit(int(WORKSPACE_OPEN_SOUND_IDS[screen_id]), false, false, true)
	_render_screen(true)


func handle_back() -> bool:
	if setup_controller.handle_back():
		return true
	if _system_return_to_setup and _view != null and _view.party_setup_available:
		_system_return_to_setup = false
		route_exiting.emit(_screen_id)
		_screen_id = &"exploration"
		_route_history.clear()
		setup_controller.show_party_setup()
		_body_frame.visible = false
		screen_changed.emit(_screen_id)
		return true
	if _screen_id == &"vault" and _workspace_presenter.handle_vault_back():
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
		_workspace_presenter.sync_route_audio(previous)
		_render_screen(true)
		return true
	if _screen_id != &"exploration":
		route_exiting.emit(_screen_id)
		_screen_id = &"exploration"
		_workspace_presenter.sync_route_audio(_screen_id)
		_render_screen(true)
		return true
	return false


func _show_load_workspace() -> void:
	if _view == null or not _view.session_started or not _view.party_setup_available:
		return
	_load_after_campaign_selection = false
	_system_return_to_setup = true
	_route_history.clear()
	open_screen(&"system")


func current_screen() -> StringName:
	return _screen_id


func primary_workspace_id() -> StringName:
	return _workspace_view.route_id if _workspace_view != null else &""


func mounted_primary_workspace_count() -> int:
	var count := 0
	for child: Node in _workspace_host.get_children():
		if child is ClassicRouteScreen:
			count += 1
	return count


func primary_workspace_visible() -> bool:
	return _workspace_view != null and _workspace_view.visible


func party_order_draft_ids() -> Array[String]:
	return _workspace_presenter.party_order_draft_ids()


func select_inventory_character(character_id: String) -> bool:
	if _screen_id != &"inventory" or not _workspace_presenter.select_inventory_character(character_id):
		return false
	_render_screen()
	return true


func select_character(character_id: String) -> bool:
	if not _workspace_presenter.select_character(character_id):
		return false
	if _screen_id == &"character":
		_render_screen()
	return true


func _build_body() -> void:
	_mount_workspace(_screen_id)


func _workspace_layout_rect() -> Rect2:
	if _screen_id == &"vault":
		return _modal_layout_rect
	if _screen_id == &"spells":
		return _spell_workspace_rect
	if _screen_id in [&"exploration", &"combat"]:
		return _workspace_rect
	return _application_workspace_rect


func _mount_workspace(screen_id: StringName) -> void:
	if _workspace_view != null and _workspace_view.route_id == screen_id:
		return
	if _workspace_view != null:
		_workspace_host.remove_child(_workspace_view)
		_workspace_view.queue_free()
	var definition := UiRouteCatalog.route(screen_id)
	var scene := load(String(definition.get("scene", ""))) as PackedScene
	if scene == null:
		push_error("Missing Classic route scene for %s" % screen_id)
		return
	_workspace_view = scene.instantiate() as ClassicRouteScreen
	_workspace_view.name = "WorkspaceFrame"
	_workspace_view.back_requested.connect(func() -> void: handle_back())
	_workspace_host.add_child(_workspace_view)
	_workspace_host.move_child(_workspace_view, 0)
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
	_body_frame.visible = not setup_controller.full_stage_overlay_visible() and _screen_id not in [&"exploration", &"combat"]
	if _screen_id in [&"character", &"vault"]:
		setup_controller.ensure_appearance_textures()
	var vault_back_label := "Back to party setup" if _vault_return_to_setup else "Back to campaigns" if _vault_return_to_campaign else "Back"
	var context_actions := _workspace_view.context_action_control() if _workspace_view != null and _screen_id == &"spells" else null
	_workspace_presenter.present(_screen_id, _body, setup_controller.appearance_textures(), vault_back_label, context_actions)
	if _workspace_view != null:
		_workspace_view.apply_route_chrome()
	if _screen_id in [&"exploration", &"combat"]:
		call_deferred("_complete_route_render", transition_revision, false, previous_scroll_horizontal, previous_scroll_vertical)
		return
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


func _show_vault_from_campaign() -> void:
	_vault_return_to_campaign = true
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	setup_controller.hide_overlays()
	_screen_id = &"vault"
	_body_frame.visible = true
	screen_changed.emit(_screen_id)
	_render_screen()


func show_vault_from_splash() -> void:
	_vault_return_to_splash = true
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	setup_controller.hide_overlays()
	_screen_id = &"vault"
	_body_frame.visible = true
	screen_changed.emit(_screen_id)
	_render_screen()


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
		_body_scroll.scroll_horizontal = 0
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
