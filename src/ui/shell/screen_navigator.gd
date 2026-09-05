## Presents screen navigator through the Godot interface.

class_name ScreenNavigator
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

const SCREEN_CONTENT_PRESENTER := preload("res://src/ui/shell/screen_content_presenter.gd")
const WORKSPACE_OPEN_SOUND_IDS: Dictionary = {
	&"inventory": 20001,
	&"spells": 20002,
}

@export_file("*.tscn") var message_label_scene_path := "res://src/ui/shared/screen_message_label.tscn"
@export_file("*.tscn") var summary_card_scene_path := "res://src/ui/shared/screen_summary_card.tscn"

var _view: GameView
var _screen_id: StringName = &"exploration"
var _body_scroll: ScrollContainer
var _body: VBoxContainer
var _body_frame: PanelContainer
var _workspace_view: ScreenFrame
var _route_history: Array[StringName] = []
var _route_transition_revision: int = 0
var _focus_controller := WorkspaceFocusController.new()
var _workspace_rect := Rect2(220.0, 100.0, 512.0, 430.0)
var _spell_screen_rect := Rect2(928.0, 28.0, 352.0, 502.0)
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
var content_presenter := SCREEN_CONTENT_PRESENTER.new()
var setup_controller := CampaignPartySetupController.new()
var _initialized: bool = false
var _startup_splash_enabled: bool = true
var full_stage_overlay_visible: bool:
	get:
		return setup_controller.full_stage_overlay_visible() or _screen_id == &"vault"


func _init() -> void:
	setup_controller.campaign_library.start_requested.connect(func(package_path: String, seed: int) -> void: start_requested.emit(package_path, seed))
	setup_controller.campaign_library.cancel_package_requested.connect(func() -> void: cancel_package_requested.emit())
	setup_controller.campaign_library.refresh_requested.connect(func() -> void: refresh_requested.emit())
	setup_controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	setup_controller.standalone_character_creation_requested.connect(func() -> void: standalone_character_creation_requested.emit())
	setup_controller.standalone_character_creation_cancelled.connect(func() -> void: standalone_character_creation_cancelled.emit())
	setup_controller.campaign_library.campaign_selection_requested.connect(func() -> void: show_campaign_selection())
	setup_controller.campaign_library.load_adventure_requested.connect(func() -> void: show_campaign_selection(true))
	setup_controller.load_saved_adventure_requested.connect(_show_load_workspace)
	setup_controller.campaign_library.vault_requested.connect(show_vault_from_splash)
	setup_controller.campaign_library.quit_requested.connect(func() -> void: system_action_requested.emit(&"quit", null))
	content_presenter.intent_submitted.connect(func(intent: PlayerIntent) -> void: intent_submitted.emit(intent))
	content_presenter.system_action_requested.connect(func(action_id: StringName, value: Variant) -> void: system_action_requested.emit(action_id, value))
	content_presenter.presentation_setting_changed.connect(func(setting_id: StringName, value: Variant) -> void: presentation_setting_changed.emit(setting_id, value))
	content_presenter.vault_archive_requested.connect(func(character_id: String) -> void: vault_archive_requested.emit(character_id))
	content_presenter.vault_restore_requested.connect(func(character_id: String, revision_hash: String) -> void: vault_restore_requested.emit(character_id, revision_hash))
	content_presenter.route_requested.connect(func(screen_id: StringName) -> void: open_screen(screen_id))
	content_presenter.refresh_requested.connect(func() -> void: refresh_current_workspace())
	content_presenter.back_requested.connect(func() -> void: handle_back())
	content_presenter.sound_requested.connect(func(sound_id: int, wait_for_completion: bool, stop_existing: bool, reduced_sound_eligible: bool) -> void: presentation_sound_requested.emit(sound_id, wait_for_completion, stop_existing, reduced_sound_eligible))


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	content_presenter.set_component_scene_paths(message_label_scene_path, summary_card_scene_path)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The router spans the window for layout only. Its panels and workspace own
	# input; the router itself must not cover menus or other shell controls.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_hosts()
	setup_controller.attach(_overlay_host)
	_build_body()
	setup_controller.campaign_library.build_splash_overlay()
	setup_controller.campaign_library.build_campaign_overlay()
	setup_controller.build_setup_overlay()
	if _startup_splash_enabled:
		show_splash()
	else:
		setup_controller.hide_overlays()
		_set_workspace_visible(false)


func set_startup_splash_enabled(enabled: bool) -> void:
	_startup_splash_enabled = enabled


func _ensure_hosts() -> void:
	_workspace_host = get_node_or_null("WorkspaceHost") as Control
	_overlay_host = get_node_or_null("OverlayHost") as Control
	assert(_workspace_host != null and _overlay_host != null, "ScreenNavigator must be instantiated from its authored scene")


func present(view: GameView) -> void:
	var completed_party_setup := _party_setup_completed(_view, view)
	_view = view
	content_presenter.set_view(view)
	if view == null or not view.session_started:
		setup_controller.present(view)
		_set_workspace_visible(false)
		return
	if not _presented_campaign_id.is_empty() and _presented_campaign_id != view.campaign_id:
		setup_controller.character_creation.reset_creator(true)
		content_presenter.reset_campaign()
	_presented_campaign_id = view.campaign_id
	setup_controller.present(view)
	if view.party_setup_available:
		if _load_after_campaign_selection:
			_load_after_campaign_selection = false
			_show_load_workspace()
			return
		if _system_return_to_setup and _screen_id == &"system":
			setup_controller.hide_overlays()
			refresh_current_workspace()
			return
		setup_controller.show_party_setup()
		_set_workspace_visible(false)
		call_deferred("_apply_modal_layouts")
		Callable(_focus_controller, "focus_first").call_deferred(setup_controller.setup_overlay)
		return
	if completed_party_setup:
		_finish_party_setup_navigation()
	setup_controller.hide_overlays()
	refresh_current_workspace()


static func _party_setup_completed(previous_view: GameView, next_view: GameView) -> bool:
	return previous_view != null and previous_view.party_setup_available and next_view != null and next_view.session_started and not next_view.party_setup_available


func _finish_party_setup_navigation() -> void:
	_vault_return_to_setup = false
	_vault_return_to_campaign = false
	_load_after_campaign_selection = false
	_system_return_to_setup = false
	content_presenter.clear_vault_inspection()
	setup_controller.finish_party_setup_navigation()
	_route_history.clear()
	if _screen_id == &"exploration":
		return
	_screen_id = &"exploration"
	content_presenter.sync_route_audio(_screen_id)
	screen_changed.emit(_screen_id)


func set_vault_revisions(revisions: Array[CharacterVaultRevisionView]) -> void:
	content_presenter.set_vault_revisions(revisions)
	setup_controller.set_vault_revisions(revisions)
	if _screen_id == &"vault":
		refresh_current_workspace()
	elif setup_controller.setup_overlay != null and setup_controller.setup_overlay.visible:
		setup_controller.character_creation.refresh_setup_options()


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	if _media == media:
		return
	_media = media
	content_presenter.set_media_catalog(media)
	setup_controller.set_media_catalog(media)
	if _view != null and _view.session_started:
		refresh_current_workspace()


func set_presentation_settings(settings: PresentationSettings) -> void:
	if settings == null:
		return
	content_presenter.set_presentation_settings(settings)
	setup_controller.character_creation.set_presentation_settings(settings)
	if _screen_id == &"system":
		refresh_current_workspace()


func set_layout_profile(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2 = Vector2.ZERO) -> void:
	if profile == null:
		return
	_layout_profile = profile.id
	content_presenter.set_layout_profile(profile.id)
	var top := profile.menu_height
	var bottom := profile.bottom_height
	_workspace_rect = Rect2(origin + Vector2(0.0, top), Vector2(maxf(320.0, viewport_size.x - profile.party_width), maxf(220.0, viewport_size.y - top - bottom)))
	_spell_screen_rect = spell_screen_rect_for(profile, viewport_size, origin)
	_full_height_workspace_rect = Rect2(origin + Vector2(0.0, top), Vector2(maxf(320.0, viewport_size.x - profile.party_width), maxf(220.0, viewport_size.y - top)))
	_application_workspace_rect = Rect2(origin + Vector2(0.0, top), Vector2(maxf(320.0, viewport_size.x), maxf(220.0, viewport_size.y - top)))
	_modal_layout_rect = Rect2(origin + Vector2(12.0, top + 8.0), Vector2(maxf(320.0, viewport_size.x - 24.0), maxf(300.0, viewport_size.y - top - 16.0)))
	_campaign_layout_rect = ScreenNavigator.campaign_rect_for(profile, viewport_size, origin)
	_setup_layout_rect = _modal_layout_rect
	if setup_controller.setup_overlay != null:
		setup_controller.apply_layout(profile, _campaign_layout_rect, _setup_layout_rect)
	_apply_modal_layouts()
	refresh_current_workspace()


static func campaign_rect_for(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2 = Vector2.ZERO) -> Rect2:
	var modal_rect := Rect2(origin + Vector2(12.0, profile.menu_height + 8.0), Vector2(maxf(320.0, viewport_size.x - 24.0), maxf(300.0, viewport_size.y - profile.menu_height - 16.0)))
	var campaign_width := clampf(228.0 * profile.ui_scale, 200.0, minf(268.0, modal_rect.size.x * 0.32))
	return Rect2(modal_rect.position, Vector2(campaign_width, modal_rect.size.y))


static func spell_screen_rect_for(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2 = Vector2.ZERO) -> Rect2:
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
	_set_workspace_visible(false)


func show_campaign_selection(load_after_selection: bool = false) -> void:
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	_load_after_campaign_selection = load_after_selection
	_system_return_to_setup = false
	setup_controller.show_campaign_selection()
	_set_workspace_visible(false)
	call_deferred("_prepare_campaign_selection")


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
	content_presenter.sync_route_audio(screen_id)
	if changed and play_opening_sound and WORKSPACE_OPEN_SOUND_IDS.has(screen_id):
		presentation_sound_requested.emit(int(WORKSPACE_OPEN_SOUND_IDS[screen_id]), false, false, true)
	refresh_current_workspace(true)


func handle_back() -> bool:
	if setup_controller.handle_back():
		return true
	if _system_return_to_setup and _view != null and _view.party_setup_available:
		_system_return_to_setup = false
		route_exiting.emit(_screen_id)
		_screen_id = &"exploration"
		_route_history.clear()
		setup_controller.show_party_setup()
		_set_workspace_visible(false)
		screen_changed.emit(_screen_id)
		return true
	if _screen_id == &"vault" and content_presenter.handle_vault_back():
		return true
	if _screen_id == &"vault" and _vault_return_to_setup and _view != null and _view.party_setup_available:
		_vault_return_to_setup = false
		_screen_id = &"exploration"
		setup_controller.show_party_setup()
		_set_workspace_visible(false)
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
			refresh_current_workspace()
			return true
		show_splash()
		return true
	if setup_controller.campaign_library.splash_visible():
		return false
	if setup_controller.setup_overlay.visible:
		return false
	if not _route_history.is_empty():
		var previous: StringName = _route_history.pop_back()
		route_exiting.emit(_screen_id)
		_screen_id = previous
		content_presenter.sync_route_audio(previous)
		refresh_current_workspace(true)
		return true
	if _screen_id != &"exploration":
		route_exiting.emit(_screen_id)
		_screen_id = &"exploration"
		content_presenter.sync_route_audio(_screen_id)
		refresh_current_workspace(true)
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
		if child is ScreenFrame:
			count += 1
	return count


func primary_workspace_visible() -> bool:
	return _workspace_view != null and _workspace_view.visible


func _build_body() -> void:
	_mount_workspace(_screen_id)


func _workspace_layout_rect() -> Rect2:
	if _screen_id == &"vault":
		return _modal_layout_rect
	if _screen_id == &"spells":
		return _spell_screen_rect
	if _screen_id in [&"exploration", &"combat"]:
		return _workspace_rect
	return _application_workspace_rect


func _mount_workspace(screen_id: StringName) -> void:
	if _workspace_view != null and _workspace_view.route_id == screen_id:
		return
	_release_workspace()
	var definition := UiRouteCatalog.route(screen_id)
	if definition == null:
		push_error("Missing UI route definition for %s" % screen_id)
		return
	if not definition.is_workspace():
		return
	if not definition.has_workspace_scene():
		push_error("Missing workspace scene for %s" % screen_id)
		return
	var workspace_scene := definition.load_workspace_scene()
	if workspace_scene == null:
		push_error("Workspace scene could not be loaded for %s" % screen_id)
		return
	_workspace_view = workspace_scene.instantiate() as ScreenFrame
	_workspace_view.name = "WorkspaceFrame"
	_workspace_view.back_requested.connect(func() -> void: handle_back())
	_workspace_host.add_child(_workspace_view)
	_workspace_host.move_child(_workspace_view, 0)
	_workspace_view.set_workspace_rect(_workspace_layout_rect())
	_body_frame = _workspace_view
	_body_scroll = _workspace_view.scroll_control()
	_body = _workspace_view.body_control()


func _release_workspace() -> void:
	if _workspace_view != null:
		_workspace_host.remove_child(_workspace_view)
		_workspace_view.queue_free()
	_workspace_view = null
	_body_frame = null
	_body_scroll = null
	_body = null


func _set_workspace_visible(visible: bool) -> void:
	if _body_frame != null:
		_body_frame.visible = visible




func refresh_current_workspace(notify_route_change: bool = false) -> void:
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
	_set_workspace_visible(not setup_controller.full_stage_overlay_visible())
	if _screen_id in [&"character", &"vault"]:
		setup_controller.character_creation.ensure_appearance_textures()
	var vault_back_label := "Back to party setup" if _vault_return_to_setup else "Back to campaigns" if _vault_return_to_campaign else "Back"
	var context_actions := _workspace_view.context_action_control() if _workspace_view != null and _screen_id == &"spells" else null
	content_presenter.present(_screen_id, _workspace_view, setup_controller.character_creation.appearance_textures(), vault_back_label, context_actions)
	if _workspace_view != null:
		_workspace_view.apply_route_chrome()
	if _screen_id in [&"exploration", &"combat"]:
		call_deferred("_complete_route_render", transition_revision, false, previous_scroll_horizontal, previous_scroll_vertical)
		return
	_focus_controller.prepare(_body, _screen_id)
	call_deferred("_complete_route_render", transition_revision, mounted_new_route, previous_scroll_horizontal, previous_scroll_vertical)


func _complete_route_render(transition_revision: int, reset_scroll_to_top: bool, previous_scroll_horizontal: int, previous_scroll_vertical: int) -> void:
	if transition_revision != _route_transition_revision:
		return
	var focus_key := _focus_controller.restore(self, _body, _body_scroll, _screen_id, reset_scroll_to_top, previous_scroll_horizontal, previous_scroll_vertical)
	workspace_focus_restored.emit(_screen_id, focus_key)


func _show_vault_from_campaign() -> void:
	_vault_return_to_campaign = true
	_vault_return_to_setup = false
	_vault_return_to_splash = false
	setup_controller.hide_overlays()
	_screen_id = &"vault"
	_set_workspace_visible(true)
	screen_changed.emit(_screen_id)
	refresh_current_workspace()


func show_vault_from_splash() -> void:
	_vault_return_to_splash = true
	_vault_return_to_campaign = false
	_vault_return_to_setup = false
	setup_controller.hide_overlays()
	_screen_id = &"vault"
	_set_workspace_visible(true)
	screen_changed.emit(_screen_id)
	refresh_current_workspace()


func _store_focus() -> void:
	_focus_controller.store(self, _screen_id)
