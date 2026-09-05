## Applies responsive shell dimensions to the stable controls authored in game_shell.tscn.
class_name GameShellLayoutController
extends RefCounted

var workspace_rect: Rect2
var _menu_strip: PanelContainer
var _menu_row: HBoxContainer
var _compact_menu: MenuButton
var _stage_frame: NinePatchRect
var _activity_indicator: PanelContainer
var _party_roster: ClassicPartyRoster
var _bottom_row: BoxContainer
var _facts: GridContainer
var _world_command_panel: PanelContainer
var _command_panel: PanelContainer
var _effects_panel: PanelContainer
var _narrative_well: PanelContainer
var _world_command_column: VBoxContainer
var _party_effects_row: BoxContainer
var _party_command_column: VBoxContainer
var _world_command_grid: GridContainer
var _command_grid: GridContainer
var _bottom_region: PanelContainer
var _picture_stage: Control
var _navigator: ScreenNavigator
var _effect_slots: Array[TextureRect] = []


func _init(shell: Control) -> void:
	_menu_strip = shell.get_node("%MenuStrip") as PanelContainer
	_menu_row = shell.get_node("%MenuRow") as HBoxContainer
	_compact_menu = shell.get_node("%CompactMenu") as MenuButton
	_stage_frame = shell.get_node("%StageFrame") as NinePatchRect
	_activity_indicator = shell.get_node("%ActivityIndicator") as PanelContainer
	_party_roster = shell.get_node("%PartyRoster") as ClassicPartyRoster
	_bottom_row = shell.get_node("%BottomRow") as BoxContainer
	_facts = shell.get_node("%Facts") as GridContainer
	_world_command_panel = shell.get_node("%WorldCommandPanel") as PanelContainer
	_command_panel = shell.get_node("%CommandPanel") as PanelContainer
	_effects_panel = shell.get_node("%EffectsPanel") as PanelContainer
	_narrative_well = shell.get_node("%NarrativeWell") as PanelContainer
	_world_command_column = shell.get_node("BottomRegion/BottomRow/WorldCommandPanel/WorldCommandColumn") as VBoxContainer
	_party_effects_row = shell.get_node("%PartyEffectsRow") as BoxContainer
	_party_command_column = shell.get_node("%PartyCommandColumn") as VBoxContainer
	_world_command_grid = shell.get_node("%WorldCommandGrid") as GridContainer
	_command_grid = shell.get_node("%CommandGrid") as GridContainer
	_bottom_region = shell.get_node("%BottomRegion") as PanelContainer
	_picture_stage = shell.get_node("%PictureStage") as Control
	_navigator = shell.get_node("%ScreenNavigator") as ScreenNavigator


func set_effect_slots(effect_slots: Array[TextureRect]) -> void:
	_effect_slots = effect_slots


func apply(shell_size: Vector2, settings: PresentationSettings, game_view: GameView) -> UiLayoutProfile:
	var profile := UiLayoutProfile.for_viewport(shell_size, settings.ui_scale_mode)
	var canvas_rect := profile.application_rect
	var viewport_size := canvas_rect.size
	var origin := canvas_rect.position
	_menu_row.visible = profile.id != UiLayoutProfile.COMPACT
	_compact_menu.visible = profile.id == UiLayoutProfile.COMPACT
	profile.menu_height = maxf(profile.menu_height, ceilf(_menu_strip.get_combined_minimum_size().y))
	var stage_width := maxf(320.0, viewport_size.x - profile.party_width)
	var stage_height := maxf(220.0, viewport_size.y - profile.menu_height - profile.bottom_height)
	var stage_rect := Rect2(origin + Vector2(0.0, profile.menu_height), Vector2(stage_width, stage_height))
	_apply_stage(profile, viewport_size, origin, stage_rect)
	var roster_width := GameShellLayoutPolicy.combat_spellbook_roster_width(viewport_size.x, profile.party_width, profile.ui_scale, _party_roster.combat_spellbook_active())
	_apply_roster(profile, viewport_size, origin, stage_height, roster_width)
	_apply_footer(profile, viewport_size, origin, stage_rect, game_view)
	_navigator.set_layout_profile(profile, viewport_size, origin)
	workspace_rect = Rect2(stage_rect.position, Vector2(GameShellLayoutPolicy.combat_spellbook_stage_width(stage_rect.size.x, viewport_size.x, roster_width), stage_rect.size.y))
	return profile


func _apply_stage(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2, stage_rect: Rect2) -> void:
	_menu_strip.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu_strip.position = origin
	_menu_strip.size = Vector2(viewport_size.x, profile.menu_height)
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
	_party_roster.z_index = GameShellLayoutPolicy.party_roster_z_index(_party_roster.combat_spellbook_active())


func _apply_footer(profile: UiLayoutProfile, viewport_size: Vector2, origin: Vector2, stage_rect: Rect2, game_view: GameView) -> void:
	_bottom_row.vertical = false
	_facts.columns = 3 if profile.id == UiLayoutProfile.COMPACT else 6
	var command_width := minf(profile.command_width, viewport_size.x * 0.26)
	_world_command_panel.visible = profile.id != UiLayoutProfile.COMPACT
	_world_command_panel.theme_type_variation = &"ClassicSharedStone"
	_command_panel.theme_type_variation = &"ClassicSharedStone"
	var side_command_width := maxf(300.0 * profile.ui_scale, command_width)
	_world_command_panel.custom_minimum_size.x = side_command_width if _world_command_panel.visible else 0.0
	_world_command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _world_command_panel.visible else Control.SIZE_SHRINK_BEGIN
	_world_command_panel.size_flags_stretch_ratio = 1.0
	_command_panel.visible = _navigator.current_screen() != &"spells"
	_effects_panel.visible = _command_panel.visible and game_view != null and game_view.session_started
	_command_panel.custom_minimum_size.x = side_command_width if _world_command_panel.visible else command_width
	_command_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _world_command_panel.visible else Control.SIZE_SHRINK_END
	_command_panel.size_flags_stretch_ratio = 1.0
	_command_panel.custom_minimum_size.y = 0.0
	var footer_width := GameShellLayoutPolicy.exploration_footer_width(viewport_size, profile, _navigator.current_screen())
	_narrative_well.custom_minimum_size.x = minf(620.0 * profile.ui_scale, maxf(360.0, footer_width - _world_command_panel.custom_minimum_size.x - _command_panel.custom_minimum_size.x - 12.0)) if _world_command_panel.visible else maxf(360.0, footer_width - (command_width if _command_panel.visible else 0.0) - 12.0)
	_narrative_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrative_well.size_flags_stretch_ratio = 1.45 if _world_command_panel.visible else 1.0
	_apply_footer_alignment(profile, command_width)
	_bottom_region.position = origin + Vector2(0.0, viewport_size.y - profile.bottom_height)
	_bottom_region.size = Vector2(footer_width, profile.bottom_height)


func _apply_footer_alignment(profile: UiLayoutProfile, command_width: float) -> void:
	_world_command_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_party_effects_row.vertical = not _world_command_panel.visible
	_party_effects_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_party_command_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_world_command_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_world_command_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_command_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_command_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_world_command_grid.columns = 4
	_command_grid.columns = 2 if _world_command_panel.visible else maxi(2, floori(command_width / (108.0 if profile.bitmap_scale == 2 else 58.0)))
	var icon_size := GameShellLayoutPolicy.party_effect_icon_size(profile.bitmap_scale)
	var slot_size := GameShellLayoutPolicy.party_effect_slot_size(profile.bitmap_scale)
	for icon: TextureRect in _effect_slots:
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		(icon.get_parent().get_parent() as Control).custom_minimum_size = Vector2(slot_size, slot_size)
