## Aligns the shell's authored stage with the algorithmic map and interaction presenters.
class_name ApplicationSpatialLayout
extends RefCounted

var _map: ClassicMapPresenter
var _battlefield: ClassicBattlefieldPresenter
var _dungeon: DungeonMap3DPresenter
var _interaction: InteractionPresenter
var _shell: GameShell
var _session: GameSessionController
var _presentation: PresentationCoordinator


func _init(
		map: ClassicMapPresenter,
		battlefield: ClassicBattlefieldPresenter,
		dungeon: DungeonMap3DPresenter,
		interaction: InteractionPresenter,
		shell: GameShell,
		session: GameSessionController,
		presentation: PresentationCoordinator
) -> void:
	_map = map
	_battlefield = battlefield
	_dungeon = dungeon
	_interaction = interaction
	_shell = shell
	_session = session
	_presentation = presentation


func apply(workspace_rect: Rect2, profile: UiLayoutProfile) -> void:
	var content_rect := workspace_rect.grow(-8.0)
	_place_presenter(_map, content_rect)
	_place_presenter(_battlefield, content_rect)
	if _dungeon != null:
		_dungeon.position = content_rect.position
		_dungeon.size = content_rect.size
	var projection_size := MapPresentationGeometry.projection_cells_for(_map.size, _map.map_origin.y, _map.cell_size)
	if _session.set_map_projection_size(projection_size):
		_presentation.refresh_spatial_projection()
	var canvas_rect := profile.application_rect
	var textbox_rect := classic_textbox_rect(workspace_rect, profile.bottom_height, canvas_rect.size.x)
	textbox_rect.position.x = canvas_rect.position.x
	var combat_rect := classic_combat_rect(canvas_rect.size, profile.bottom_height)
	combat_rect.position += canvas_rect.position
	_interaction.set_classic_regions(content_rect, textbox_rect, combat_rect)
	_sync_narrative_after_layout(content_rect, combat_rect)


static func classic_textbox_rect(workspace_rect: Rect2, bottom_height: float, full_width: float = 0.0) -> Rect2:
	var width := full_width if full_width > 0.0 else workspace_rect.size.x
	return Rect2(0.0 if full_width > 0.0 else workspace_rect.position.x, workspace_rect.end.y, width, bottom_height)


static func classic_combat_rect(viewport_size: Vector2, bottom_height: float) -> Rect2:
	return Rect2(0.0, maxf(0.0, viewport_size.y - bottom_height), viewport_size.x, minf(bottom_height, viewport_size.y))


static func _place_presenter(presenter: Control, content_rect: Rect2) -> void:
	presenter.set_anchors_preset(Control.PRESET_TOP_LEFT)
	presenter.position = content_rect.position
	presenter.size = content_rect.size


func _sync_narrative_after_layout(content_rect: Rect2, combat_rect: Rect2) -> void:
	await _shell.get_tree().process_frame
	var narrative_rect := _shell.status.narrative_region(_shell)
	if narrative_rect.has_area():
		_interaction.set_classic_regions(content_rect, narrative_rect, combat_rect)
