## Applies responsive shell dimensions to the stable controls authored in game_shell.tscn.
class_name GameShellLayoutController
extends RefCounted

var _shell_ref: WeakRef
var _footer_pending := false
var workspace_rect: Rect2
var applied_profile: UiLayoutProfile
var _stage_frame: NinePatchRect
var _activity_indicator: PanelContainer
var _party_roster: ClassicPartyRoster
var _bottom_row: BoxContainer
var _facts: GridContainer
var _world_command_panel: PanelContainer
var _command_panel: PanelContainer
var _effects_panel: PanelContainer
var _torch_dock: PanelContainer
var _narrative_well: PanelContainer
var _world_command_column: VBoxContainer
var _party_effects_row: BoxContainer
var _party_command_column: VBoxContainer
var _world_command_grid: GridContainer
var _world_command_lower_grid: GridContainer
var _command_grid: GridContainer
var _bottom_region: PanelContainer
var _picture_stage: Control
var _navigator: ScreenNavigator
var _effect_slots: Array[TextureRect] = []
var _authored_roster_width: float
var _authored_footer_height: float
var _authored_command_width: float


func _init(shell: Control) -> void:
	_shell_ref = weakref(shell)
	_stage_frame = shell.get_node("%StageFrame") as NinePatchRect
	_activity_indicator = shell.get_node("%ActivityIndicator") as PanelContainer
	_party_roster = shell.get_node("%PartyRoster") as ClassicPartyRoster
	_bottom_row = shell.get_node("%BottomRow") as BoxContainer
	_facts = shell.get_node("%Facts") as GridContainer
	_world_command_panel = shell.get_node("%WorldCommandPanel") as PanelContainer
	_command_panel = shell.get_node("%CommandPanel") as PanelContainer
	_effects_panel = shell.get_node("%EffectsPanel") as PanelContainer
	_torch_dock = shell.get_node("%TorchDock") as PanelContainer
	_narrative_well = shell.get_node("%NarrativeWell") as PanelContainer
	_world_command_column = shell.get_node("BottomRegion/BottomRow/WorldCommandPanel/WorldCommandColumn") as VBoxContainer
	_party_effects_row = shell.get_node("%PartyEffectsRow") as BoxContainer
	_party_command_column = shell.get_node("%PartyCommandColumn") as VBoxContainer
	_world_command_grid = shell.get_node("%WorldCommandGrid") as GridContainer
	_world_command_lower_grid = shell.get_node("%WorldCommandLowerGrid") as GridContainer
	_command_grid = shell.get_node("%CommandGrid") as GridContainer
	_bottom_region = shell.get_node("%BottomRegion") as PanelContainer
	_picture_stage = shell.get_node("%PictureStage") as Control
	_navigator = shell.get_node("%ScreenNavigator") as ScreenNavigator
	_authored_roster_width = _party_roster.offset_right - _party_roster.offset_left
	_authored_footer_height = _bottom_region.offset_bottom - _bottom_region.offset_top
	_authored_command_width = _world_command_panel.custom_minimum_size.x


func set_effect_slots(effect_slots: Array[TextureRect]) -> void:
	_effect_slots = effect_slots


func bind_hud_content(shell: GameShell, modular: bool) -> void:
	if modular:
		_party_roster = shell.hud.content(0) as ClassicPartyRoster
		_narrative_well = shell.hud.content(1) as PanelContainer
		_world_command_panel = shell.hud.content(2) as PanelContainer
		_command_panel = shell.hud.content(3) as PanelContainer
		_facts = _narrative_well.get_node("NarrativeColumn/Facts") as GridContainer
	else:
		_party_roster = shell.get_node("%PartyRoster") as ClassicPartyRoster
		_narrative_well = shell.get_node("%NarrativeWell") as PanelContainer
		_world_command_panel = shell.get_node("%WorldCommandPanel") as PanelContainer
		_command_panel = shell.get_node("%CommandPanel") as PanelContainer
		_facts = shell.get_node("%Facts") as GridContainer
	_world_command_column = _world_command_panel.get_node("WorldCommandColumn") as VBoxContainer
	_party_effects_row = _command_panel.get_node("PartyEffectsRow") as BoxContainer
	_party_command_column = _party_effects_row.get_node("PartyCommandColumn") as VBoxContainer
	_world_command_grid = shell.hud.world_grid if modular else shell.get_node("%WorldCommandGrid") as GridContainer
	_world_command_lower_grid = _world_command_panel.get_node("WorldCommandColumn/WorldCommandDeckCenter/WorldCommandDeckFrame/WorldCommandRows/WorldCommandLowerCenter/WorldCommandLowerGrid") as GridContainer
	_command_grid = shell.hud.party_grid() if modular else shell.get_node("%CommandGrid") as GridContainer
	_torch_dock = _party_effects_row.get_node("TorchDock") as PanelContainer
	_effects_panel = shell.hud.effects_panel if modular else shell.get_node("%EffectsPanel") as PanelContainer


func apply(shell_size: Vector2, settings: PresentationSettings, game_view: GameView) -> UiLayoutProfile:
	var profile := UiLayoutProfile.for_viewport(shell_size, settings.ui_scale_mode, settings.display_scaling_mode, settings.interface_text_scale, settings.narrative_text_scale)
	var shell := _shell_ref.get_ref() as GameShell
	if profile.id == UiLayoutProfile.WIDE:
		profile.party_width = _authored_roster_width * profile.ui_scale
		profile.bottom_height = _authored_footer_height * profile.ui_scale
		profile.command_width = _authored_command_width * profile.ui_scale
	else:
		profile.party_width = (shell.compact_roster_width * maxf(1.0, settings.interface_text_scale) + shell.compact_roster_text_growth * maxf(0.0, settings.interface_text_scale - 1.0)) * profile.ui_scale
		profile.bottom_height = shell.compact_footer_height * profile.ui_scale
		profile.command_width = shell.compact_command_width * profile.ui_scale
	var canvas_rect := profile.application_rect
	var viewport_size := canvas_rect.size
	var origin := canvas_rect.position
	profile.menu_height = 0.0
	var modular := shell.hud.prepare(settings, game_view, _navigator.current_screen(), shell.pause_active)
	if modular:
		_apply_modular(profile)
		applied_profile = profile
		return profile
	_apply_footer(profile, viewport_size, origin, game_view)
	profile.bottom_height = maxf(profile.bottom_height, ceilf(_bottom_region.get_combined_minimum_size().y))
	if game_view != null and game_view.combat_view != null:
		profile.bottom_height = maxf(profile.bottom_height, 190.0 * profile.font_scale)
	var stage_width := maxf(320.0, viewport_size.x - profile.party_width)
	var stage_height := maxf(1.0, viewport_size.y - profile.menu_height - profile.bottom_height)
	var stage_rect := Rect2(origin + Vector2(0.0, profile.menu_height), Vector2(stage_width, stage_height))
	_apply_stage(profile, viewport_size, origin, stage_rect)
	var roster_width := GameShellLayoutPolicy.combat_spellbook_roster_width(viewport_size.x, profile.party_width, profile.ui_scale, _party_roster.combat_spellbook_active(), settings.interface_text_scale)
	_apply_roster(profile, viewport_size, origin, stage_height, roster_width)
	restore_footer_bounds(profile)
	_navigator.set_layout_profile(profile, viewport_size, origin)
	workspace_rect = Rect2(stage_rect.position, Vector2(GameShellLayoutPolicy.combat_spellbook_stage_width(stage_rect.size.x, viewport_size.x, roster_width), stage_rect.size.y))
	applied_profile = profile
	return profile


func _apply_modular(profile: UiLayoutProfile) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	var area := profile.application_rect
	_world_command_panel.show()
	_command_panel.show()
	_narrative_well.show()
	_party_roster.show()
	_bottom_region.hide()
	_world_command_panel.custom_minimum_size = Vector2.ZERO
	_command_panel.custom_minimum_size = Vector2.ZERO
	_narrative_well.custom_minimum_size = Vector2.ZERO
	_facts.columns = 3 if profile.font_scale <= 1.0 else 2
	_apply_footer_alignment(profile, profile.command_width)
	_apply_stage(profile, area.size, area.position, area)
	shell.hud.arrange(profile)
	_navigator.set_layout_profile(profile, area.size, area.position)
	workspace_rect = area


func _apply_stage(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2, stage_rect: Rect2) -> void:
	_stage_frame.position = stage_rect.position
	_stage_frame.size = stage_rect.size
	_activity_indicator.position = stage_rect.position + Vector2(10.0, 10.0)
	_activity_indicator.size = Vector2(40.0, 40.0)
	var picture_size := Vector2(minf(560.0 * profile.ui_scale, stage_rect.size.x - 48.0), minf(360.0 * profile.ui_scale, stage_rect.size.y - 48.0))
	_picture_stage.position = stage_rect.position + (stage_rect.size - picture_size) * 0.5
	_picture_stage.size = picture_size


func _apply_roster(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2, stage_height: float, roster_width: float) -> void:
	_party_roster.position = origin + Vector2(viewport_size.x - roster_width, profile.menu_height)
	_party_roster.size = Vector2(roster_width, GameShellLayoutPolicy.party_roster_height(viewport_size.y, profile.menu_height, stage_height, _party_roster.combat_spellbook_active()))
	_party_roster.set_compact_layout(profile.id == UiLayoutProfile.COMPACT)
	_party_roster.z_index = GameShellLayoutPolicy.party_roster_z_index(_party_roster.combat_spellbook_active())


func _apply_footer(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2, game_view: GameView) -> void:
	_bottom_row.vertical = false
	_facts.columns = (1 if profile.font_scale > profile.ui_scale else 2) if profile.id == UiLayoutProfile.COMPACT else (3 if profile.font_scale > profile.ui_scale else 6)
	var command_width := minf(profile.command_width, viewport_size.x * (0.52 if profile.id == UiLayoutProfile.COMPACT else 0.26))
	_world_command_panel.visible = profile.id != UiLayoutProfile.COMPACT
	_world_command_panel.theme_type_variation = &"ClassicSharedStone"
	_command_panel.theme_type_variation = &"ClassicSharedStone"
	var side_command_width := maxf(300.0 * profile.ui_scale, command_width)
	_world_command_panel.custom_minimum_size.x = side_command_width if _world_command_panel.visible else 0.0
	_world_command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _world_command_panel.visible else Control.SIZE_SHRINK_BEGIN
	_world_command_panel.size_flags_stretch_ratio = 1.0
	_command_panel.visible = _navigator.current_screen() != &"spells"
	_effects_panel.visible = _command_panel.visible and game_view != null and game_view.session_started
	_torch_dock.visible = _command_panel.visible and _navigator.current_screen() == &"exploration"
	if profile.id != UiLayoutProfile.COMPACT:
		_command_panel.custom_minimum_size.x = side_command_width if _world_command_panel.visible else command_width
	_command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _world_command_panel.visible else Control.SIZE_SHRINK_END
	_command_panel.size_flags_stretch_ratio = 1.0
	_command_panel.custom_minimum_size.y = 0.0
	var footer_width := GameShellLayoutPolicy.exploration_footer_width(viewport_size, profile, _navigator.current_screen())
	_narrative_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrative_well.size_flags_stretch_ratio = 1.45 if _world_command_panel.visible else 1.0
	_apply_footer_alignment(profile, command_width)
	if profile.id != UiLayoutProfile.COMPACT:
		var sides_width := (_world_command_panel.get_combined_minimum_size().x if _world_command_panel.visible else 0.0) + (_command_panel.get_combined_minimum_size().x if _command_panel.visible else 0.0)
		var chrome_width := ceilf(_bottom_region.get_theme_stylebox("panel").get_minimum_size().x) + ceilf(_bottom_row.get_theme_constant("separation")) * 2.0
		_narrative_well.custom_minimum_size.x = maxf(120.0 * profile.ui_scale, minf(620.0 * profile.ui_scale, footer_width - sides_width - chrome_width))
	if profile.id == UiLayoutProfile.COMPACT:
		var content_width := _party_effects_row.get_combined_minimum_size().x + _command_panel.get_theme_stylebox("panel").get_minimum_size().x
		_command_panel.custom_minimum_size.x = maxf(command_width, content_width) if _command_panel.visible else 0.0
		var chrome_width := _bottom_region.get_theme_stylebox("panel").get_minimum_size().x + _bottom_row.get_theme_constant("separation")
		_narrative_well.custom_minimum_size.x = maxf(120.0, footer_width - _command_panel.custom_minimum_size.x - chrome_width)
	restore_footer_bounds(profile)


func restore_footer_bounds(profile: UiLayoutProfile) -> void:
	var shell := _shell_ref.get_ref() as GameShell
	if shell.hud != null and shell.hud.active: return
	var canvas_rect := profile.application_rect
	var footer_width := GameShellLayoutPolicy.exploration_footer_width(canvas_rect.size, profile, _navigator.current_screen())
	_bottom_region.position = canvas_rect.position + Vector2(0.0, canvas_rect.size.y - profile.bottom_height)
	_bottom_region.size = Vector2(footer_width, profile.bottom_height)


func _apply_footer_alignment(profile: UiLayoutProfile, command_width: float) -> void:
	_world_command_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_party_effects_row.vertical = false
	_party_effects_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_party_command_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_world_command_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_world_command_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_command_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_command_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not (_shell_ref.get_ref() as GameShell).hud.active:
		_world_command_grid.columns = 4
		_world_command_lower_grid.columns = 3
		_command_grid.columns = 2 if _world_command_panel.visible else 3 if profile.id == UiLayoutProfile.COMPACT else maxi(2, floori(command_width / (108.0 if profile.bitmap_scale == 2 else 58.0)))
	var icon_size := GameShellLayoutPolicy.party_effect_icon_size(profile.bitmap_scale)
	var slot_size := GameShellLayoutPolicy.party_effect_slot_size(profile.bitmap_scale)
	for icon: TextureRect in _effect_slots:
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		(icon.get_parent().get_parent() as Control).custom_minimum_size = Vector2(slot_size, slot_size)


func queue_footer_layout() -> void:
	if _footer_pending: return
	_footer_pending = true
	call_deferred("_settle_footer_layout")


func _settle_footer_layout() -> void:
	_footer_pending = false
	var shell := _shell_ref.get_ref() as GameShell
	if shell == null or not shell.is_node_ready() or applied_profile == null: return
	apply(shell.size, shell.settings, shell.current_view)
	shell.layout_changed.emit(workspace_rect, applied_profile)
