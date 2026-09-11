## Binds detached campaign-library data to the authored front-door scenes.

class_name CampaignLibraryController
extends RefCounted

const CAMPAIGN_SELECTION_PANEL_SCENE := preload("res://src/ui/setup/campaign_selection_panel.tscn")
const FRONT_DOOR_MENU_PATH := "res://src/ui/setup/front_door_menu.tscn"

signal start_requested(package_path: String, seed: int)
signal cancel_package_requested
signal refresh_requested
signal campaign_selection_requested
signal load_adventure_requested
signal vault_requested
signal quit_requested

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
var install_button: Button
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
var _no_campaigns_state: Label
var _selected_summary: PanelContainer
var _selected_title: Label
var _selected_splash: TextureRect
var _selected_splash_unavailable: Label
var _selected_byline: Label
var _selected_restrictions: Label
var _selected_limits: Label
var _selected_guidance: Label
var _operation_phase: Label
var _operation_percentage: Label
var _operation_progress: ProgressBar
var _operation_cancel: Button
var _operation_status: Label
var _startup_actions_ready: bool = true
var _startup_action_tooltips: Dictionary = {}


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
	var panel := CAMPAIGN_SELECTION_PANEL_SCENE.instantiate() as CampaignSelectionPanel
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
	_operation_phase = campaign_overlay.get_node("%PackageOperationPhase") as Label
	_operation_percentage = campaign_overlay.get_node("%PackageOperationPercentage") as Label
	_operation_progress = campaign_overlay.get_node("%PackageOperationProgress") as ProgressBar
	_operation_cancel = campaign_overlay.get_node("%CancelPackageOperation") as Button
	_operation_status = campaign_overlay.get_node("%PackageOperationStatus") as Label
	package_install_row = campaign_overlay.get_node("%PackageInstallRow") as BoxContainer
	install_button = campaign_overlay.get_node("%InstallPackage") as Button
	install_dialog = campaign_overlay.get_node("%InstallScenarioDialog") as FileDialog
	refresh_button = campaign_overlay.get_node("%RefreshScenarios") as Button
	install_button.pressed.connect(_open_package_dialog)
	install_dialog.file_selected.connect(_install_selected)
	refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	_operation_cancel.pressed.connect(func() -> void: cancel_package_requested.emit())
	render_campaign_list()


func set_campaigns(next_campaigns: Array[CampaignPackageView]) -> void:
	campaigns = next_campaigns.duplicate()
	campaigns.sort_custom(_campaign_precedes)
	render_campaign_list()


func set_package_operation(status: RefCounted) -> void:
	package_operation_status = status if status != null else PackageOperationView.new()
	render_campaign_list()


func set_selected_campaign_summary(summary: CampaignSummaryView) -> void:
	selected_campaign_summary = summary
	render_campaign_list()


func set_media_catalog(next_media: ClassicMediaCatalog) -> void:
	media = next_media
	if selected_campaign_summary != null:
		render_campaign_list()


func set_presentation_settings(next_settings: PresentationSettings) -> void:
	if next_settings != null:
		settings = next_settings
		_apply_intro_volume()


func set_startup_actions_ready(ready: bool) -> void:
	_startup_actions_ready = ready
	for button: Button in startup_action_buttons:
		button.disabled = not ready
		button.tooltip_text = str(_startup_action_tooltips.get(button.name, "")) if ready else "Finishing startup…"
	if ready and splash_overlay != null and splash_overlay.visible:
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
		package_install_row.vertical = profile.id == UiLayoutProfile.COMPACT
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


func full_stage_overlay_visible() -> bool:
	return splash_visible() or campaign_overlay != null and campaign_overlay.visible


func splash_visible() -> bool:
	return splash_overlay != null and splash_overlay.visible


func render_campaign_list() -> void:
	if campaign_list == null:
		return
	_remove_campaign_rows()
	_render_package_operation()
	_render_selected_campaign_record()
	var running: bool = package_operation_status.is_running()
	if campaigns.is_empty():
		_no_campaigns_state.text = "No installed scenarios. Install a Providence .realmz2 package below."
		_no_campaigns_state.visible = not running
		_refresh_campaign_layout()
		return
	var ready_count := 0
	var hidden_count := 0
	for campaign: CampaignPackageView in campaigns:
		if not campaign.ready:
			hidden_count += 1
			continue
		ready_count += 1
		var action := _campaign_row_scene.instantiate() as Button
		action.set_meta(&"campaign_record", true)
		action.name = "Scenario_%s" % (campaign.campaign_id if not campaign.campaign_id.is_empty() else campaign.path.get_file()).validate_node_name()
		action.text = "%s\nInstalled • ready" % _display_name(campaign)
		action.tooltip_text = campaign.path
		var selected := selected_campaign_summary != null and campaign.campaign_id == selected_campaign_summary.campaign_id
		action.disabled = running or selected
		action.button_pressed = selected
		if selected:
			action.text = "%s\nSelected • party setup open" % _display_name(campaign)
			action.tooltip_text = "This scenario is selected."
		action.pressed.connect(_campaign_pressed.bind(campaign))
		campaign_list.add_child(action)
		campaign_list.move_child(action, _no_campaigns_state.get_index())
	_no_campaigns_state.text = "No playable scenarios. Install a package from the current Providence exporter."
	_no_campaigns_state.visible = ready_count == 0 and not running
	campaign_overlay.tooltip_text = "%d incompatible or stale installation%s hidden from the ordinary scenario list." % [hidden_count, "" if hidden_count == 1 else "s"] if hidden_count > 0 else "Installed Providence scenarios."
	_refresh_campaign_layout()


func _render_package_operation() -> void:
	var running: bool = package_operation_status.is_running()
	var failed: bool = package_operation_status.state == PackageOperationView.FAILED
	package_operation_host.visible = running or failed
	install_button.disabled = running
	refresh_button.disabled = running
	_operation_progress.visible = running
	_operation_percentage.visible = running
	_operation_cancel.visible = running
	if not running and not failed:
		return
	var phase_text := String(package_operation_status.phase).replace("_", " ").capitalize()
	_operation_phase.text = "Could not open scenario" if failed else phase_text if not phase_text.is_empty() else "Installing"
	_operation_percentage.text = "%d%%" % int(round(package_operation_status.progress_ratio() * 100.0)) if package_operation_status.total > 0 else "Working"
	_operation_progress.indeterminate = package_operation_status.total <= 0
	_operation_progress.max_value = maxf(1.0, float(package_operation_status.total))
	_operation_progress.value = clampf(float(package_operation_status.completed), 0.0, _operation_progress.max_value)
	_operation_status.text = package_operation_status.message
	_operation_status.tooltip_text = package_operation_status.message


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
	if selected_campaign_summary.guidance_authored:
		if selected_campaign_summary.recommended_party_levels > 0:
			guidance.append("recommended party total %d" % selected_campaign_summary.recommended_party_levels)
		if selected_campaign_summary.maximum_party_levels > 0:
			guidance.append("maximum %d" % selected_campaign_summary.maximum_party_levels)
	_selected_guidance.text = " • ".join(guidance)
	_selected_guidance.visible = not guidance.is_empty()


func _remove_campaign_rows() -> void:
	for child: Node in campaign_list.get_children():
		if child.has_meta(&"campaign_record"):
			campaign_list.remove_child(child)
			child.queue_free()


func _campaign_pressed(campaign: CampaignPackageView) -> void:
	if campaign.ready:
		start_requested.emit(campaign.path, 1)


func _open_package_dialog() -> void:
	if install_dialog != null:
		install_dialog.popup_centered_ratio(0.7)


func _install_selected(path: String) -> void:
	if path.get_extension().to_lower() == "realmz2":
		start_requested.emit(path, 1)


func _refresh_campaign_layout() -> void:
	apply_modal_layouts()
	if campaign_scroll != null:
		campaign_scroll.scroll_vertical = 0


func _display_name(campaign: CampaignPackageView) -> String:
	if not campaign.display_name.strip_edges().is_empty():
		return campaign.display_name.strip_edges()
	return campaign.campaign_id.replace("-", " ").capitalize()


func _campaign_precedes(left: CampaignPackageView, right: CampaignPackageView) -> bool:
	if left.ready != right.ready:
		return left.ready
	return _display_name(left).naturalnocasecmp_to(_display_name(right)) < 0


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
