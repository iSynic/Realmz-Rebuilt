## Binds detached campaign-library data to the authored front-door scenes.

class_name CampaignLibraryController
extends RefCounted

const CAMPAIGN_SELECTION_PANEL_PATH := "res://src/ui/setup/campaign_selection_panel.tscn"
const FRONT_DOOR_MENU_PATH := "res://src/ui/setup/front_door_menu.tscn"
const STARTUP_SELECTION_CONTROLLER := preload("res://src/ui/setup/campaign_startup_selection_controller.gd")
## Folder imports use Castle's scenario-first rule-table branch, regardless of title.
const IMPORTED_SCENARIO_RULE_SELECTION: int = 20

signal start_requested(package_path: String, seed: int)
signal import_requested(directory: String, native_menu_selection: int, startup_file: String)
signal startup_selection_requested(directory: String, native_menu_selection: int, startup_file: String)
signal revision_requested(campaign_id: String, package_hash: String)
signal removal_requested(campaign_id: String)
signal cancel_package_requested
signal refresh_requested
signal campaign_selection_requested
signal load_adventure_requested
signal vault_requested
signal quit_requested
signal preparation_changed
signal back_requested

const MAXIMUM_MODAL_Z_INDEX: int = 30
const SPLASH_WIDE_MINIMUM_WIDTH: float = 1040.0

var splash_overlay: PanelContainer
var splash_composition: BoxContainer
var splash_animation_host: NinePatchRect
var splash_animation: VideoStreamPlayer
var campaign_overlay: PanelContainer
var campaign_list: VBoxContainer
var campaign_scroll: ScrollContainer
var package_operation_host: PanelContainer
var install_dialog: FileDialog
var import_dialog: FileDialog
var install_button: Button
var import_button: Button
var refresh_button: Button
var package_install_row: BoxContainer
var startup_action_buttons: Array[Button] = []

var campaigns: Array[CampaignPackageView] = []
var package_operation_status: RefCounted = PackageOperationView.new()
var selected_campaign_summary: CampaignSummaryView
var media: ClassicMediaCatalog
var settings: PresentationSettings = PresentationSettings.new()
var campaign_layout_rect := Rect2(12.0, 36.0, 228.0, 556.0)
var setup_layout_rect := Rect2(12.0, 36.0, 936.0, 556.0)

var _host: Control
var _campaign_row_scene: PackedScene
var _main_campaign_rows: VBoxContainer
var _imported_campaign_rows: VBoxContainer
var _main_campaign_heading: Label
var _imported_campaign_heading: Label
var _no_campaigns_state: Label
var _selected_summary: PanelContainer
var _selected_title: Label
var _selected_splash: TextureRect
var _selected_splash_unavailable: Label
var _selected_byline: Label
var _selected_restrictions: Label
var _selected_limits: Label
var _selected_guidance: Label
var _package_operation := CampaignPackageOperationController.new()
var _focused_import_path: String = ""
var _selected_campaign_path: String = ""
var _requested_campaign_path: String = ""
var _pending_revision_hash := ""
var _startup_actions_ready: bool = true
var _startup_action_tooltips: Dictionary = {}
var _startup_selection: RefCounted = STARTUP_SELECTION_CONTROLLER.new()
var _remove_dialog: CampaignRemovalDialog
var _browsed_campaign_path := ""
var full_stage_overlay_visible: bool:
	get: return splash_visible or campaign_overlay != null and campaign_overlay.visible
var splash_visible: bool:
	get: return splash_overlay != null and splash_overlay.visible



func _init() -> void:
	var controller_ref: WeakRef = weakref(self)
	_package_operation.cancel_requested.connect(func() -> void:
		var controller := controller_ref.get_ref() as CampaignLibraryController
		if controller != null: controller.cancel_package_requested.emit())
	_package_operation.retry_requested.connect(func(operation: StringName, path: String, _selection: int) -> void:
		var controller := controller_ref.get_ref() as CampaignLibraryController
		if controller == null: return
		if operation == &"import_scenario": controller.import_requested.emit(path, IMPORTED_SCENARIO_RULE_SELECTION, "")
		else: controller.start_requested.emit(path, 1))
	_package_operation.dismiss_requested.connect(func() -> void:
		var controller := controller_ref.get_ref() as CampaignLibraryController
		if controller != null: controller.set_package_operation(PackageOperationView.new()))
	_startup_selection.connect("selection_requested", func(directory: String, native_menu_selection: int, startup_file: String) -> void:
		var controller := controller_ref.get_ref() as CampaignLibraryController
		if controller != null:
			controller.startup_selection_requested.emit(directory, native_menu_selection, startup_file)
	)


func attach(host: Control) -> void:
	_host = host


func build_splash_overlay() -> void:
	if splash_overlay != null:
		return
	splash_overlay = _host.get_node_or_null("SplashScreen") as PanelContainer
	if splash_overlay == null:
		var scene := load(FRONT_DOOR_MENU_PATH) as PackedScene
		assert(scene != null, "The front-door menu scene is unavailable.")
		splash_overlay = scene.instantiate() as PanelContainer
		splash_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		splash_overlay.z_index = MAXIMUM_MODAL_Z_INDEX
		_host.add_child(splash_overlay)
	splash_composition = splash_overlay.get_node("%SplashComposition") as BoxContainer
	splash_animation_host = splash_overlay.get_node("%RealmzIntroOrnament") as NinePatchRect
	splash_animation = splash_overlay.get_node("%RealmzIntroAnimation") as VideoStreamPlayer
	var scenarios := splash_overlay.get_node("%ChooseScenario") as Button
	var load_adventure := splash_overlay.get_node("%LoadAdventure") as Button
	var characters := splash_overlay.get_node("%CharacterFiles") as Button
	var quit := splash_overlay.get_node("%Quit") as Button
	scenarios.pressed.connect(func() -> void: campaign_selection_requested.emit())
	load_adventure.pressed.connect(func() -> void: load_adventure_requested.emit())
	characters.pressed.connect(func() -> void: vault_requested.emit())
	quit.pressed.connect(func() -> void: quit_requested.emit())
	startup_action_buttons.clear()
	_register_startup_action(scenarios)
	_register_startup_action(load_adventure)
	_register_startup_action(characters)
	_apply_intro_volume()
	_apply_intro_frame_layout(false)


func build_campaign_overlay() -> void:
	if campaign_overlay != null:
		return
	var panel := (load(CAMPAIGN_SELECTION_PANEL_PATH) as PackedScene).instantiate() as CampaignSelectionPanel
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.z_index = 0
	_host.add_child(panel)
	bind_campaign_panel(panel)


func bind_campaign_panel(panel: CampaignSelectionPanel) -> void:
	assert(panel != null, "The campaign-selection panel is unavailable.")
	assert(campaign_overlay == null or campaign_overlay == panel, "A different campaign-selection panel is already bound.")
	campaign_overlay = panel
	_campaign_row_scene = campaign_overlay.get("campaign_row_scene") as PackedScene
	campaign_list = campaign_overlay.get_node("%CampaignList") as VBoxContainer
	_main_campaign_rows = campaign_overlay.get_node("%MainCampaignRows") as VBoxContainer
	_imported_campaign_rows = campaign_overlay.get_node("%ImportedCampaignRows") as VBoxContainer
	_main_campaign_heading = campaign_overlay.get_node("%MainScenarioHeading") as Label
	_imported_campaign_heading = campaign_overlay.get_node("%ImportedScenarioHeading") as Label
	campaign_scroll = campaign_overlay.get_node("%CampaignScroll") as ScrollContainer
	_no_campaigns_state = campaign_overlay.get_node("%NoCampaignsState") as Label
	_selected_summary = campaign_overlay.get_node("%SelectedScenarioSummary") as PanelContainer
	_selected_title = campaign_overlay.get_node("%SelectedScenarioTitle") as Label
	_selected_splash = campaign_overlay.get_node("%SelectedScenarioSplash") as TextureRect
	_selected_splash_unavailable = campaign_overlay.get_node("%SelectedScenarioSplashUnavailable") as Label
	_selected_byline = campaign_overlay.get_node("%SelectedScenarioByline") as Label
	_selected_restrictions = campaign_overlay.get_node("%SelectedScenarioRestrictions") as Label
	_selected_limits = campaign_overlay.get_node("%SelectedScenarioLimits") as Label
	_selected_guidance = campaign_overlay.get_node("%SelectedScenarioGuidance") as Label
	package_operation_host = campaign_overlay.get_node("%PackageOperationHost") as PanelContainer
	_package_operation.bind(panel)
	_startup_selection.call("bind", campaign_overlay)
	package_install_row = campaign_overlay.get_node("%PackageInstallRow") as BoxContainer
	install_button = campaign_overlay.get_node("%InstallPackage") as Button
	import_button = campaign_overlay.get_node("%ImportScenario") as Button
	install_dialog = campaign_overlay.get_node("%InstallScenarioDialog") as FileDialog
	import_dialog = campaign_overlay.get_node("%ImportScenarioDialog") as FileDialog
	refresh_button = campaign_overlay.get_node("%RefreshScenarios") as Button
	_remove_dialog = campaign_overlay.get_node("%RemoveScenarioDialog") as CampaignRemovalDialog
	_remove_dialog.removal_confirmed.connect(func(campaign_id: String) -> void:
		if not package_operation_status.is_running(): removal_requested.emit(campaign_id))
	(campaign_overlay as CampaignSelectionPanel).revision_selected.connect(func(id: String, hash_value: String) -> void: revision_requested.emit(id, hash_value))
	(campaign_overlay as CampaignSelectionPanel).removal_requested.connect(func(id: String, title: String) -> void: _remove_dialog.present(id, title))
	(campaign_overlay as CampaignSelectionPanel).back_requested.connect(func() -> void: back_requested.emit())
	install_button.pressed.connect(_open_package_dialog)
	install_dialog.file_selected.connect(_install_selected)
	import_dialog.dir_selected.connect(func(directory: String) -> void: import_requested.emit(directory, IMPORTED_SCENARIO_RULE_SELECTION, ""))
	import_button.pressed.connect(_open_import_dialog)
	refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	_render_campaign_list()


func set_campaigns(next_campaigns: Array[CampaignPackageView]) -> void:
	campaigns = next_campaigns.duplicate()
	_render_campaign_list()


func set_package_operation(status: RefCounted) -> void:
	var was_running: bool = package_operation_status.is_running()
	package_operation_status = status if status != null else PackageOperationView.new()
	if not package_operation_status.is_running(): _pending_revision_hash = ""
	if was_running != package_operation_status.is_running():
		_render_campaign_list()
	else:
		_render_package_operation()
	if was_running != package_operation_status.is_running(): preparation_changed.emit()


func set_selected_campaign_summary(summary: CampaignSummaryView) -> void:
	selected_campaign_summary = summary
	_render_campaign_list()


func set_media_catalog(next_media: ClassicMediaCatalog) -> void:
	media = next_media
	if selected_campaign_summary != null:
		_render_campaign_list()


func set_presentation_settings(next_settings: PresentationSettings) -> void:
	if next_settings != null:
		settings = next_settings
		_apply_intro_volume()


func set_startup_actions_ready(ready: bool) -> void:
	var became_ready := ready and not _startup_actions_ready
	_startup_actions_ready = ready
	for button: Button in startup_action_buttons:
		button.disabled = not ready
		button.tooltip_text = str(_startup_action_tooltips.get(button.name, "")) if ready else "Finishing startup…"
	if ready and splash_overlay != null and splash_overlay.visible:
		if became_ready and not startup_action_buttons.is_empty():
			startup_action_buttons[0].grab_focus()
		else:
			_focus_first(splash_overlay)


func apply_layout(profile: UiLayoutProfile, campaign_rect: Rect2, setup_rect: Rect2) -> void:
	if profile == null:
		return
	campaign_layout_rect = campaign_rect
	setup_layout_rect = setup_rect
	if splash_composition != null:
		splash_composition.vertical = false
		var identity_panel := splash_composition.find_child("SplashIdentityPanel", false, false) as Control
		var command_panel := splash_composition.find_child("SplashCommandPanel", false, false) as Control
		if identity_panel != null:
			identity_panel.custom_minimum_size = Vector2.ZERO
		if command_panel != null:
			command_panel.custom_minimum_size = Vector2(320.0, 0.0)
		_apply_intro_frame_layout(setup_rect.size.x < SPLASH_WIDE_MINIMUM_WIDTH)
	if package_install_row != null:
		package_install_row.vertical = false
		install_button.text = "Install..." if profile.id == UiLayoutProfile.COMPACT else "Install .realmz2"
	apply_modal_layouts()


func apply_modal_layouts() -> void:
	if splash_overlay != null:
		splash_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		splash_overlay.position = setup_layout_rect.position
		splash_overlay.size = setup_layout_rect.size
	if campaign_overlay != null and campaign_overlay.get_parent() == _host:
		campaign_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
		campaign_overlay.position = campaign_layout_rect.position
		campaign_overlay.size = campaign_layout_rect.size


func show_campaign() -> void:
	if campaign_overlay != null:
		campaign_overlay.visible = true
	if splash_overlay != null:
		splash_overlay.visible = false
	_set_intro_active(false)
	apply_modal_layouts()
	if campaign_scroll != null:
		campaign_scroll.scroll_vertical = 0
	if not _focused_import_path.is_empty():
		_reveal_focused_import()


func select_imported_package(path: String) -> void:
	for campaign: CampaignPackageView in campaigns:
		if campaign.origin == "imported" and campaign.path == path:
			_focused_import_path = path
			_browsed_campaign_path = path
			if campaign_overlay != null:
				campaign_overlay.visible = true
				if splash_overlay != null:
					splash_overlay.visible = false
				_set_intro_active(false)
				apply_modal_layouts()
				_render_campaign_list()
				_reveal_focused_import()
			(campaign_overlay as CampaignSelectionPanel).reveal_campaign(campaign)
			return

func select_prepared_package(path: String) -> void:
	for campaign: CampaignPackageView in campaigns:
		if campaign.origin == "main" and campaign.path == _requested_campaign_path and selected_campaign_summary != null and campaign.package_hash == selected_campaign_summary.package_hash:
			_selected_campaign_path = campaign.path
			_render_campaign_list()
			return
	_selected_campaign_path = path
	select_imported_package(path)


func preview_revision(campaign: CampaignPackageView, package_hash: String, path: String) -> void:
	_browsed_campaign_path = campaign.path
	_requested_campaign_path = path
	_pending_revision_hash = package_hash


func show_splash() -> void:
	if splash_overlay == null:
		return
	splash_overlay.visible = true
	_set_intro_active(true)
	if campaign_overlay != null:
		campaign_overlay.visible = false
	apply_modal_layouts()
	_focus_first(splash_overlay)


func hide_overlays() -> void:
	if splash_overlay != null:
		splash_overlay.visible = false
	if campaign_overlay != null:
		campaign_overlay.visible = false
	_set_intro_active(false)


func prepare_intro_behind_splash() -> void:
	var intro := splash_animation as ClassicIntroAnimation
	if intro == null:
		return
	intro.prepare()
	intro.start_playback()


func release_intro_resources() -> void:
	var intro := splash_animation as ClassicIntroAnimation
	if intro != null:
		intro.release_resources()


func _set_intro_active(active: bool) -> void:
	var intro := splash_animation as ClassicIntroAnimation
	if intro == null:
		return
	if active:
		intro.start_playback()
	else:
		intro.suspend_playback()


func _render_campaign_list() -> void:
	if campaign_list == null:
		return
	var focused := campaign_overlay.get_viewport().gui_get_focus_owner()
	var restore_path := ""
	if focused != null and campaign_list.is_ancestor_of(focused):
		var parent := focused.get_parent()
		while parent != null and not parent is CampaignLibraryRow: parent = parent.get_parent()
		if parent is CampaignLibraryRow: restore_path = parent.package_path()
	elif focused == _package_operation.cancel_button:
		restore_path = _selected_campaign_path
	_remove_campaign_rows(_main_campaign_rows)
	_remove_campaign_rows(_imported_campaign_rows)
	_render_package_operation()
	_render_selected_campaign_record()
	var running: bool = package_operation_status.is_running()
	var ordered_campaigns: Array[CampaignPackageView] = []
	var imported_campaigns: Array[CampaignPackageView] = []
	for campaign: CampaignPackageView in campaigns:
		if campaign.origin == "main":
			ordered_campaigns.append(campaign)
		else:
			imported_campaigns.append(campaign)
	imported_campaigns.sort_custom(func(left: CampaignPackageView, right: CampaignPackageView) -> bool: return _display_name(left).naturalnocasecmp_to(_display_name(right)) < 0)
	ordered_campaigns.append_array(imported_campaigns)
	for campaign: CampaignPackageView in ordered_campaigns:
		var row := _campaign_row_scene.instantiate() as Control
		row.set_meta(&"campaign_record", true)
		row.name = "Scenario_%s" % (campaign.campaign_id if not campaign.campaign_id.is_empty() else campaign.path.get_file()).validate_node_name()
		row.connect("campaign_pressed", _campaign_pressed.bind(campaign))
		var destination := _main_campaign_rows if campaign.origin == "main" else _imported_campaign_rows
		destination.add_child(row)
		row.call("configure", campaign, not running and _campaign_matches_selection(campaign), running, _focused_import_path == campaign.path)
	_main_campaign_heading.visible = _has_visible_origin("main")
	_imported_campaign_heading.visible = _has_visible_origin("imported")
	_no_campaigns_state.text = "No installed scenarios. Install a .realmz2 package or import a scenario folder below."
	_no_campaigns_state.visible = campaigns.is_empty() and not running
	campaign_overlay.tooltip_text = "Installed scenarios. Unavailable entries remain visible with their readiness reason."
	apply_modal_layouts()
	var browsed: CampaignPackageView
	for campaign: CampaignPackageView in ordered_campaigns:
		if campaign.path == _browsed_campaign_path or (browsed == null and _campaign_matches_selection(campaign)):
			browsed = campaign
	(campaign_overlay as CampaignSelectionPanel).present_campaign(browsed, running, browsed != null and _campaign_matches_selection(browsed), _pending_revision_hash)
	if not restore_path.is_empty(): _restore_list_focus.call_deferred(restore_path)


func _restore_list_focus(path: String) -> void:
	if not is_instance_valid(campaign_overlay) or not campaign_overlay.is_visible_in_tree(): return
	if package_operation_status.is_running():
		_package_operation.cancel_button.grab_focus()
		return
	for rows: VBoxContainer in [_main_campaign_rows, _imported_campaign_rows]:
		for row: CampaignLibraryRow in rows.get_children():
			if row.package_path() == path and row.is_visible_in_tree(): row.get_node("%LaunchCampaign").grab_focus()


func _render_package_operation() -> void:
	var running: bool = package_operation_status.is_running()
	install_button.disabled = running
	import_button.disabled = running
	refresh_button.disabled = running
	var needs_startup: bool = _startup_selection.call("present", package_operation_status, package_operation_status.state == PackageOperationView.FAILED)
	_package_operation.present(package_operation_status, needs_startup)


func _render_selected_campaign_record() -> void:
	_selected_summary.visible = selected_campaign_summary != null
	if selected_campaign_summary == null:
		return
	_selected_title.text = selected_campaign_summary.title
	_selected_title.tooltip_text = selected_campaign_summary.title
	_selected_splash.texture = null
	_selected_splash.visible = false
	_selected_splash_unavailable.visible = false
	if not selected_campaign_summary.splash_asset_id.is_empty():
		var asset := media.asset_by_id(selected_campaign_summary.splash_asset_id) if media != null else null
		var texture := media.image_texture(asset) if media != null and asset != null else null
		_selected_splash.texture = texture
		_selected_splash.visible = texture != null
		_selected_splash_unavailable.visible = texture == null
	var byline_parts: Array[String] = []
	if not selected_campaign_summary.version.is_empty():
		byline_parts.append("v%s" % selected_campaign_summary.version)
	if not selected_campaign_summary.author.is_empty():
		byline_parts.append("by %s" % selected_campaign_summary.author)
	_selected_byline.text = " • ".join(byline_parts)
	_selected_byline.visible = not byline_parts.is_empty()
	var restrictions := selected_campaign_summary.restriction_description.strip_edges()
	_selected_restrictions.text = restrictions
	_selected_restrictions.tooltip_text = restrictions
	_selected_restrictions.visible = not restrictions.is_empty()
	var limits: Array[String] = ["Up to %d characters" % selected_campaign_summary.maximum_party_size]
	if selected_campaign_summary.maximum_level > 0:
		limits.append("character level cap %d" % selected_campaign_summary.maximum_level)
	_selected_limits.text = " • ".join(limits)
	var guidance: Array[String] = []
	if selected_campaign_summary.recommended_party_levels > 0 or selected_campaign_summary.maximum_party_levels > 0:
		if selected_campaign_summary.recommended_party_levels > 0:
			guidance.append("recommended party total %d" % selected_campaign_summary.recommended_party_levels)
		if selected_campaign_summary.maximum_party_levels > 0:
			guidance.append("maximum %d" % selected_campaign_summary.maximum_party_levels)
	if selected_campaign_summary.compatibility_warning_count > 0:
		guidance.append("%d deferred legacy reference warning%s" % [selected_campaign_summary.compatibility_warning_count, "" if selected_campaign_summary.compatibility_warning_count == 1 else "s"])
	_selected_guidance.text = " • ".join(guidance)
	_selected_guidance.tooltip_text = "\n".join(selected_campaign_summary.compatibility_warning_summaries)
	_selected_guidance.visible = not guidance.is_empty()


func _remove_campaign_rows(host: VBoxContainer) -> void:
	for child: Node in host.get_children():
		if child.has_meta(&"campaign_record"):
			host.remove_child(child)
			child.queue_free()


func _campaign_pressed(campaign: CampaignPackageView) -> void:
	_browsed_campaign_path = campaign.path
	_render_campaign_list()
	if campaign.ready and not _campaign_matches_selection(campaign):
		_requested_campaign_path = campaign.path
		start_requested.emit(campaign.path, 1)


func _open_package_dialog() -> void:
	if install_dialog != null:
		install_dialog.popup_centered_ratio(0.7)


func _open_import_dialog() -> void:
	if import_dialog != null:
		import_dialog.popup_centered_ratio(0.7)


func _install_selected(path: String) -> void:
	if path.get_extension().to_lower() == "realmz2":
		_requested_campaign_path = path
		start_requested.emit(path, 1)


func _display_name(campaign: CampaignPackageView) -> String:
	if not campaign.display_name.strip_edges().is_empty():
		return campaign.display_name.strip_edges()
	return campaign.campaign_id.replace("-", " ").capitalize()


func _campaign_matches_selection(campaign: CampaignPackageView) -> bool:
	if selected_campaign_summary == null or campaign.campaign_id != selected_campaign_summary.campaign_id:
		return false
	if not _selected_campaign_path.is_empty() and not selected_campaign_summary.package_hash.is_empty() and not campaign.package_hash.is_empty():
		if campaign.package_hash == selected_campaign_summary.package_hash:
			return campaign.path == _selected_campaign_path
	if not selected_campaign_summary.package_hash.is_empty() and not campaign.package_hash.is_empty():
		return campaign.package_hash == selected_campaign_summary.package_hash
	return true


func _has_visible_origin(origin: String) -> bool:
	for campaign: CampaignPackageView in campaigns:
		if campaign.origin == origin:
			return true
	return false


func _reveal_focused_import() -> void:
	if _focused_import_path.is_empty() or _imported_campaign_rows == null or campaign_scroll == null:
		return
	(campaign_overlay as CampaignSelectionPanel).call_deferred("_reveal_path", _focused_import_path)


func _focus_first(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.is_inside_tree() and control.visible and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return
		_focus_first(child)
		var viewport := _host.get_viewport() if _host != null else null
		var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
		if focus_owner != null and parent.is_ancestor_of(focus_owner):
			return


func _register_startup_action(button: Button) -> void:
	startup_action_buttons.append(button)
	_startup_action_tooltips[button.name] = button.tooltip_text
	button.disabled = not _startup_actions_ready
	if not _startup_actions_ready:
		button.tooltip_text = "Finishing startup…"


func _apply_intro_frame_layout(compact: bool) -> void:
	if splash_animation_host == null or splash_animation == null:
		return
	var host_size := Vector2(308.0, 198.0) if compact else Vector2(630.0, 410.0)
	var inset := Vector2(24.0, 24.0) if compact else Vector2(55.0, 55.0)
	splash_animation_host.custom_minimum_size = host_size
	splash_animation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash_animation.offset_left = inset.x
	splash_animation.offset_top = inset.y
	splash_animation.offset_right = -inset.x
	splash_animation.offset_bottom = -inset.y


func _apply_intro_volume() -> void:
	if splash_animation == null:
		return
	var value := clampf(settings.master_volume, 0.0, 1.0)
	if splash_animation is ClassicIntroAnimation:
		(splash_animation as ClassicIntroAnimation).set_master_volume(value)
	else:
		splash_animation.volume_db = -80.0
