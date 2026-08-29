class_name CampaignLibraryController
extends RefCounted

const PackageOperationViewScript := preload("res://src/app/package_operation_view.gd")
const ClassicIntroAnimationScript := preload("res://src/presentation/classic_intro_animation.gd")
const INTRO_FRAME_TEXTURE_PATH := "res://src/presentation/assets/ui/classic-intro-frame.png"

signal start_requested(package_path: String, seed: int)
signal cancel_package_requested
signal refresh_requested
signal campaign_selection_requested
signal load_adventure_requested
signal vault_requested
signal quit_requested

const GOLD := Color("d5b45d")
const MUTED := Color("9aa0a8")
const MAXIMUM_MODAL_Z_INDEX: int = 30

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
var package_operation_status: RefCounted = PackageOperationViewScript.new()
var selected_campaign_summary: CampaignSummaryView
var media: ClassicMediaCatalog
var settings: PresentationSettings = PresentationSettings.new()
var campaign_layout_rect := Rect2(12.0, 36.0, 228.0, 556.0)
var setup_layout_rect := Rect2(12.0, 36.0, 936.0, 556.0)

var _host: Control
var _startup_actions_ready: bool = true
var _startup_action_tooltips: Dictionary = {}
var _intro_frame_texture: Texture2D = load(INTRO_FRAME_TEXTURE_PATH) as Texture2D


func attach(host: Control) -> void:
	_host = host


func build_splash_overlay() -> void:
	if splash_overlay != null:
		return
	splash_overlay = PanelContainer.new()
	splash_overlay.name = "SplashScreen"
	splash_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	surface.border_color = Color("4b5157")
	surface.set_border_width_all(1)
	surface.content_margin_left = 24.0
	surface.content_margin_top = 20.0
	surface.content_margin_right = 24.0
	surface.content_margin_bottom = 20.0
	splash_overlay.add_theme_stylebox_override("panel", surface)
	splash_overlay.z_index = MAXIMUM_MODAL_Z_INDEX
	_host.add_child(splash_overlay)
	splash_composition = BoxContainer.new()
	splash_composition.name = "SplashComposition"
	splash_composition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	splash_composition.size_flags_vertical = Control.SIZE_EXPAND_FILL
	splash_composition.add_theme_constant_override("separation", 18)
	splash_overlay.add_child(splash_composition)
	var identity_panel := PanelContainer.new()
	identity_panel.name = "SplashIdentityPanel"
	identity_panel.theme_type_variation = &"ClassicInset"
	identity_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	identity_panel.size_flags_stretch_ratio = 1.65
	splash_composition.add_child(identity_panel)
	var identity_center := CenterContainer.new()
	identity_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	identity_panel.add_child(identity_center)
	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = 360.0
	identity.add_theme_constant_override("separation", 10)
	identity_center.add_child(identity)
	var title := _splash_label("Realmz Rebuilt", GOLD, 42)
	title.name = "SplashTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.add_child(title)
	splash_animation_host = NinePatchRect.new()
	splash_animation_host.name = "RealmzIntroOrnament"
	splash_animation_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	splash_animation_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash_animation_host.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	splash_animation_host.texture = _intro_frame_texture
	splash_animation_host.patch_margin_left = 90
	splash_animation_host.patch_margin_top = 90
	splash_animation_host.patch_margin_right = 90
	splash_animation_host.patch_margin_bottom = 90
	identity.add_child(splash_animation_host)
	splash_animation = ClassicIntroAnimationScript.new()
	splash_animation.name = "RealmzIntroAnimation"
	splash_animation_host.add_child(splash_animation)
	_apply_intro_volume()
	_apply_intro_frame_layout(false)
	var subtitle := _splash_label("Classic Adventures Reconstructed", Color("e0e2e5"), 20)
	subtitle.name = "SplashSubtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	identity.add_child(subtitle)
	var command_panel := PanelContainer.new()
	command_panel.name = "SplashCommandPanel"
	command_panel.theme_type_variation = &"ClassicInset"
	command_panel.custom_minimum_size.x = 320.0
	command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	command_panel.size_flags_stretch_ratio = 0.75
	splash_composition.add_child(command_panel)
	var command_center := CenterContainer.new()
	command_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	command_panel.add_child(command_center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 280.0
	column.add_theme_constant_override("separation", 12)
	command_center.add_child(column)
	column.add_child(_splash_label("Begin", GOLD, 24))
	column.add_child(_splash_label("Choose an installed adventure or manage reusable adventurers.", MUTED, 15))
	var scenarios := Button.new()
	scenarios.name = "ChooseScenario"
	scenarios.text = "Choose a scenario"
	scenarios.custom_minimum_size.y = 42.0
	scenarios.pressed.connect(func() -> void: campaign_selection_requested.emit())
	_register_startup_action(scenarios)
	column.add_child(scenarios)
	var load_adventure := Button.new()
	load_adventure.name = "LoadAdventure"
	load_adventure.text = "Load saved adventure"
	load_adventure.custom_minimum_size.y = 42.0
	load_adventure.pressed.connect(func() -> void: load_adventure_requested.emit())
	_register_startup_action(load_adventure)
	column.add_child(load_adventure)
	var characters := Button.new()
	characters.name = "CharacterFiles"
	characters.text = "Character files"
	characters.tooltip_text = "Review reusable Character Files. Stock Realmz characters can be created without selecting a scenario; scenario-specific races and classes require that scenario."
	characters.custom_minimum_size.y = 42.0
	characters.pressed.connect(func() -> void: vault_requested.emit())
	_register_startup_action(characters)
	column.add_child(characters)
	var quit := Button.new()
	quit.name = "Quit"
	quit.text = "Quit"
	quit.custom_minimum_size.y = 42.0
	quit.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit)


func build_campaign_overlay() -> void:
	if campaign_overlay != null:
		return
	campaign_overlay = PanelContainer.new()
	campaign_overlay.name = "ScenarioColumn"
	campaign_overlay.theme_type_variation = &"ClassicInset"
	campaign_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	campaign_overlay.custom_minimum_size.x = 210.0
	campaign_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	campaign_overlay.size_flags_stretch_ratio = 0.72
	campaign_overlay.z_index = 0
	_host.add_child(campaign_overlay)
	var column := VBoxContainer.new()
	column.name = "ScenarioPaneContent"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	campaign_overlay.add_child(column)
	var scenario_heading := _add_label(column, "Scenarios", GOLD, 20)
	scenario_heading.name = "ScenarioHeading"
	campaign_list = VBoxContainer.new()
	campaign_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	campaign_scroll = ScrollContainer.new()
	campaign_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	campaign_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	campaign_scroll.follow_focus = true
	campaign_scroll.add_child(campaign_list)
	column.add_child(campaign_scroll)
	package_operation_host = PanelContainer.new()
	package_operation_host.name = "PackageOperationHost"
	package_operation_host.theme_type_variation = &"ClassicInset"
	package_operation_host.visible = false
	column.add_child(package_operation_host)
	package_install_row = BoxContainer.new()
	package_install_row.name = "PackageInstallRow"
	package_install_row.alignment = BoxContainer.ALIGNMENT_CENTER
	install_button = Button.new()
	install_button.name = "InstallPackage"
	install_button.text = "Install Scenario"
	install_button.custom_minimum_size = Vector2(150.0, 34.0)
	install_button.pressed.connect(_open_package_dialog)
	package_install_row.add_child(install_button)
	column.add_child(package_install_row)
	install_dialog = FileDialog.new()
	install_dialog.name = "InstallScenarioDialog"
	install_dialog.access = FileDialog.ACCESS_FILESYSTEM
	install_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	install_dialog.filters = PackedStringArray(["*.realmz2 ; Realmz Rebuilt Scenario"])
	install_dialog.use_native_dialog = true
	install_dialog.file_selected.connect(_install_selected)
	_host.add_child(install_dialog)
	refresh_button = Button.new()
	refresh_button.name = "RefreshScenarios"
	refresh_button.text = "Refresh scenarios"
	refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	var library_actions := HBoxContainer.new()
	library_actions.add_child(refresh_button)
	column.add_child(library_actions)


func set_campaigns(next_campaigns: Array[CampaignPackageView]) -> void:
	campaigns = next_campaigns.duplicate()
	campaigns.sort_custom(_campaign_precedes)
	render_campaign_list()


func set_package_operation(status: RefCounted) -> void:
	package_operation_status = status if status != null else PackageOperationViewScript.new()
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
		splash_composition.vertical = profile.id == UiLayoutProfile.COMPACT
		var identity_panel := splash_composition.find_child("SplashIdentityPanel", false, false) as Control
		var command_panel := splash_composition.find_child("SplashCommandPanel", false, false) as Control
		if identity_panel != null:
			identity_panel.custom_minimum_size = Vector2(0.0, 270.0) if splash_composition.vertical else Vector2.ZERO
		if command_panel != null:
			command_panel.custom_minimum_size = Vector2(0.0, 250.0) if splash_composition.vertical else Vector2(320.0, 0.0)
		_apply_intro_frame_layout(splash_composition.vertical)
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
	_clear(campaign_list)
	_render_package_operation()
	if selected_campaign_summary != null:
		_add_selected_campaign_record()
	if campaigns.is_empty():
		if not package_operation_status.is_running():
			_add_label(campaign_list, "No installed scenarios. Install a Providence .realmz2 package below.", MUTED)
		return
	var ready_count := 0
	var hidden_count := 0
	for campaign: CampaignPackageView in campaigns:
		if not campaign.ready:
			hidden_count += 1
			continue
		ready_count += 1
		var action := Button.new()
		action.name = "Scenario_%s" % (campaign.campaign_id if not campaign.campaign_id.is_empty() else campaign.path.get_file()).validate_node_name()
		action.custom_minimum_size = Vector2(0, 58)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.alignment = HORIZONTAL_ALIGNMENT_LEFT
		action.clip_text = true
		action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var status := "Installed • ready"
		action.text = "%s\n%s" % [_display_name(campaign), status]
		action.tooltip_text = campaign.path
		var selected := selected_campaign_summary != null and campaign.campaign_id == selected_campaign_summary.campaign_id
		action.disabled = package_operation_status.is_running() or selected
		action.toggle_mode = true
		action.button_pressed = selected
		if selected:
			action.text = "%s\nSelected • party setup open" % _display_name(campaign)
			action.tooltip_text = "This scenario is selected."
		action.pressed.connect(_campaign_pressed.bind(campaign))
		campaign_list.add_child(action)
	if ready_count == 0 and not package_operation_status.is_running():
		_add_label(campaign_list, "No playable scenarios. Install a package from the current Providence exporter.", MUTED)
	if hidden_count > 0:
		campaign_overlay.tooltip_text = "%d incompatible or stale installation%s hidden from the ordinary scenario list." % [hidden_count, "" if hidden_count == 1 else "s"]
	else:
		campaign_overlay.tooltip_text = "Installed Providence scenarios."
	_refresh_campaign_layout()

func _render_package_operation() -> void:
	if package_operation_host == null:
		return
	_clear(package_operation_host)
	var running: bool = package_operation_status.is_running()
	package_operation_host.visible = running
	install_button.disabled = running
	refresh_button.disabled = running
	if not running:
		return
	var operation := VBoxContainer.new()
	operation.name = "PackageOperationRow"
	operation.add_theme_constant_override("separation", 4)
	package_operation_host.add_child(operation)
	var header := HBoxContainer.new()
	var phase_text := String(package_operation_status.phase).replace("_", " ").capitalize()
	var phase := _label(phase_text if not phase_text.is_empty() else "Installing", GOLD, 12)
	phase.name = "PackageOperationPhase"
	header.add_child(phase)
	header.add_spacer(true)
	var progress_text := "%d%%" % int(round(package_operation_status.progress_ratio() * 100.0)) if package_operation_status.total > 0 else "Working"
	var percentage := _label(progress_text, MUTED, 11)
	percentage.name = "PackageOperationPercentage"
	header.add_child(percentage)
	operation.add_child(header)
	var controls := HBoxContainer.new()
	controls.name = "PackageOperationControls"
	var progress := ProgressBar.new()
	progress.name = "PackageOperationProgress"
	progress.custom_minimum_size = Vector2(72, 22)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.show_percentage = false
	progress.indeterminate = package_operation_status.total <= 0
	progress.max_value = maxf(1.0, float(package_operation_status.total))
	progress.value = clampf(float(package_operation_status.completed), 0.0, progress.max_value)
	controls.add_child(progress)
	var cancel := Button.new()
	cancel.name = "CancelPackageOperation"
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void: cancel_package_requested.emit())
	controls.add_child(cancel)
	operation.add_child(controls)
	var message := _add_label(operation, package_operation_status.message, MUTED, 11)
	message.name = "PackageOperationStatus"
	message.max_lines_visible = 2
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	message.tooltip_text = package_operation_status.message

func _add_selected_campaign_record() -> void:
	var panel := PanelContainer.new()
	panel.name = "SelectedScenarioSummary"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	body.add_child(_label("Selected Scenario", MUTED, 11))
	var title := _add_label(body, selected_campaign_summary.title, GOLD, 16)
	title.tooltip_text = selected_campaign_summary.title
	if not selected_campaign_summary.splash_asset_id.is_empty():
		var asset := media.asset_by_id(selected_campaign_summary.splash_asset_id) if media != null else null
		var texture := media.image_texture(asset) if media != null and asset != null else null
		if texture != null:
			var picture := TextureRect.new()
			picture.name = "SelectedScenarioSplash"
			picture.custom_minimum_size = Vector2(0.0, 92.0)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			picture.texture = texture
			body.add_child(picture)
		else:
			var missing := _add_label(body, "Campaign picture unavailable", MUTED, 11)
			missing.name = "SelectedScenarioSplashUnavailable"
	var byline_parts: Array[String] = []
	if not selected_campaign_summary.version.is_empty():
		byline_parts.append("v%s" % selected_campaign_summary.version)
	if not selected_campaign_summary.author.is_empty():
		byline_parts.append("by %s" % selected_campaign_summary.author)
	if not byline_parts.is_empty():
		_add_label(body, " • ".join(byline_parts), Color("e0e2e5"), 12)
	_add_bounded_summary(body, selected_campaign_summary.restriction_description)
	var limits: Array[String] = ["Up to %d characters" % selected_campaign_summary.maximum_party_size]
	if selected_campaign_summary.maximum_level > 0:
		limits.append("character level cap %d" % selected_campaign_summary.maximum_level)
	_add_label(body, " • ".join(limits), MUTED, 11)
	if selected_campaign_summary.guidance_authored:
		var guidance: Array[String] = []
		if selected_campaign_summary.recommended_party_levels > 0:
			guidance.append("recommended party total %d" % selected_campaign_summary.recommended_party_levels)
		if selected_campaign_summary.maximum_party_levels > 0:
			guidance.append("maximum %d" % selected_campaign_summary.maximum_party_levels)
		if not guidance.is_empty():
			_add_label(body, " • ".join(guidance), GOLD, 11)
	campaign_list.add_child(panel)

func _add_bounded_summary(parent: Container, text: String) -> void:
	var summary_text := text.strip_edges()
	if summary_text.is_empty():
		return
	var label := _add_label(parent, summary_text, Color("e0e2e5"), 11)
	label.max_lines_visible = 4
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = summary_text


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


func _label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", int(round(float(size) * settings.text_scale)))
	return label


func _splash_label(text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.theme_type_variation = &"ClassicHeading"
	return label


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


func _add_label(parent: Container, text: String, color: Color = Color.WHITE, size: int = 15) -> Label:
	var label := _label(text, color, size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _clear(parent: Node) -> void:
	if parent == null:
		return
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
