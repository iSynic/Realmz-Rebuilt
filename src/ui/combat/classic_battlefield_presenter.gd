## Presents Classic battlefield presenter through the Godot interface.

class_name ClassicBattlefieldPresenter
extends Control


const NATIVE_CELL_SIZE: float = BattlefieldPresentationGeometry.NATIVE_CELL_SIZE
const HEADER_HEIGHT: float = BattlefieldPresentationGeometry.HEADER_HEIGHT
const SURROUND_TEXTURE_PATH := "res://src/ui/shared/assets/ui/classic-exploration-surround-tile.png"

var _view: GameView
var _media: ClassicMediaCatalog
var _textures := BattlefieldTextureCache.new()
var interaction: BattlefieldInteractionController = BattlefieldInteractionController.new()
var _render_camera_top_left := Vector2i(-1, -1)
var _render_camera_focus_id: String = ""
var _render_camera_visible_cells := Vector2i.ZERO
var _playback_frame: CombatPlaybackFrame
var _monster_facing_right: Dictionary = {}
var last_playback_media_diagnostic: Dictionary = {}
var _surround_texture: Texture2D = load(SURROUND_TEXTURE_PATH) as Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	interaction.redraw_requested.connect(queue_redraw)


func present(game_view: GameView) -> void:
	_view = game_view
	_playback_frame = null
	if interaction.present(game_view):
		_render_camera_focus_id = ""
	_sync_monster_facings()
	if _view == null or _view.combat_view == null:
		_render_camera_top_left = Vector2i(-1, -1)
		_render_camera_focus_id = ""
		_render_camera_visible_cells = Vector2i.ZERO
	var requested_upper_atlas_id := ""
	if _view != null and _view.combat_view != null and _view.combat_view.battlefield != null:
		requested_upper_atlas_id = _view.combat_view.battlefield.upper_tileset_id
	_textures.prepare(requested_upper_atlas_id)
	queue_redraw()


func present_playback_frame(frame: CombatPlaybackFrame) -> void:
	if interaction.playback_changed(_playback_frame, frame):
		_render_camera_focus_id = ""
	if frame != null and frame.kind == &"move_start" and not frame.actor_id.is_empty() and frame.from_coordinate.x >= 0 and frame.to_coordinate.x >= 0:
		_monster_facing_right[frame.actor_id] = frame.to_coordinate.x > frame.from_coordinate.x
	_playback_frame = frame
	queue_redraw()


func clear_playback_frame() -> void:
	_playback_frame = null
	last_playback_media_diagnostic.clear()
	queue_redraw()


func playback_frame() -> CombatPlaybackFrame:
	return _playback_frame


func set_media_catalog(media: ClassicMediaCatalog) -> void:
	_media = media
	_textures.set_media_catalog(media)
	queue_redraw()


func has_battle_artwork() -> bool:
	return _textures.has_battle_artwork()


func _draw() -> void:
	if _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		return
	_draw_battle_stage()
	var combat := _view.combat_view
	var battlefield := combat.battlefield
	var focus_id := BattlefieldPresentationGeometry.camera_focus_id_for(_playback_frame, interaction.focused_combatant_id, combat.active_actor_id)
	var active_position := _effective_actor_position(combat, focus_id)
	if active_position.x < 0:
		active_position = battlefield.party_anchor
	var visible_cells := BattlefieldPresentationGeometry.viewport_cells_for(size)
	var camera := BattlefieldPresentationGeometry.tracked_camera_top_left(
		_render_camera_top_left,
		active_position,
		visible_cells,
		_render_camera_focus_id != focus_id or _render_camera_visible_cells != visible_cells
	)
	_render_camera_top_left = camera
	_render_camera_focus_id = focus_id
	_render_camera_visible_cells = visible_cells
	var draw_origin := BattlefieldPresentationGeometry.battlefield_draw_origin(size, visible_cells)
	_draw_header(combat)
	for y: int in visible_cells.y:
		for x: int in visible_cells.x:
			var coordinate := camera + Vector2i(x, y)
			var rect := Rect2(draw_origin + Vector2(x, y) * NATIVE_CELL_SIZE, Vector2.ONE * NATIVE_CELL_SIZE)
			_draw_terrain_cell(battlefield.terrain_at(coordinate), rect)
	_draw_persistent_fields(combat, camera, visible_cells, draw_origin)
	_draw_revealed_relationships(combat, camera, visible_cells, draw_origin)
	_draw_movement_options(combat, camera, visible_cells, draw_origin)
	_draw_targeting_preview(combat, camera, visible_cells, draw_origin)
	_draw_characters(combat, camera, visible_cells, draw_origin)
	_draw_monsters(combat, camera, visible_cells, draw_origin)
	_draw_playback_overlay(combat, camera, visible_cells, draw_origin)
	_draw_tactical_legend()
	if not has_battle_artwork():
		draw_string(_ui_font(), Vector2(draw_origin.x + 8.0, draw_origin.y + 20.0), "Battle artwork unavailable", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.78, 0.42))


func _draw_battle_stage() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.022, 0.026), true)
	if _surround_texture != null:
		draw_texture_rect(_surround_texture, Rect2(Vector2.ZERO, size), true, Color(0.34, 0.35, 0.36, 0.72))


func _draw_header(combat: CombatView) -> void:
	var current_actor_name := BattlefieldPresentationGeometry.actor_name(combat, _view.party_members, combat.active_actor_id)
	var title := "Battle %s • Round %d • %s" % [combat.battle_id, combat.round_number, current_actor_name]
	var facts := "%d attack%s • %d movement • %s" % [combat.attack_units_remaining, "" if combat.attack_units_remaining == 1 else "s", combat.movement_remaining, String(combat.weapon_mode).capitalize()]
	draw_string(_ui_font(), Vector2(8.0, 17.0), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 250.0, 120.0), 16, Color(0.86, 0.75, 0.42))
	draw_string(_ui_font(), Vector2(size.x - 242.0, 17.0), facts, HORIZONTAL_ALIGNMENT_RIGHT, 234.0, 12, Color(0.73, 0.76, 0.80))


func _draw_tactical_legend() -> void:
	if interaction.reveal_friends:
		var x := 8.0
		for entry: Array in [["Hostile", Color(0.95, 0.22, 0.18)], ["Friendly", Color(0.18, 0.90, 0.38)], ["Helpless", Color(0.20, 0.42, 1.0)]]:
			draw_line(Vector2(x, 29.0), Vector2(x + 18.0, 29.0), entry[1], 2.0)
			draw_string(_ui_font(), Vector2(x + 23.0, 33.0), String(entry[0]), HORIZONTAL_ALIGNMENT_LEFT, 58.0, 10, Color(0.82, 0.84, 0.84))
			x += 86.0
		draw_string(_ui_font(), Vector2(x, 33.0), "Click board to dismiss", HORIZONTAL_ALIGNMENT_LEFT, 126.0, 10, Color(0.63, 0.67, 0.69))
	elif interaction.movement_costs_visible:
		draw_string(_ui_font(), Vector2(8.0, 33.0), "Movement cost aid • release Shift to hide", HORIZONTAL_ALIGNMENT_LEFT, 250.0, 10, Color(0.94, 0.82, 0.38))


func _draw_terrain_cell(tile_id: int, rect: Rect2) -> void:
	var asset := _textures.terrain_asset(tile_id)
	var texture := _textures.terrain_texture(tile_id)
	var region := Rect2i() if asset == null else asset.region_for(tile_id)
	if texture != null and region.has_area():
		draw_texture_rect_region(texture, rect, Rect2(region))
		return
	var shade := 0.12 + float(posmod(tile_id, 7)) * 0.012
	draw_rect(rect, Color(shade, shade * 1.05, shade * 0.92), true)
	draw_rect(rect, Color(0.20, 0.22, 0.24), false, 1.0)


func _draw_movement_options(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	if _playback_frame != null:
		return
	for option: CombatMoveOptionView in combat.movement_options:
		if not BattlefieldPresentationGeometry.coordinate_is_visible(option.destination, camera, visible_cells):
			continue
		if not interaction.movement_costs_visible and option.destination != interaction.hovered_coordinate:
			continue
		var rect := BattlefieldPresentationGeometry.cell_rect(option.destination, camera, draw_origin).grow(-2.0)
		if option.enabled:
			draw_rect(rect, Color(0.08, 0.10, 0.08, 0.62), true)
			draw_rect(rect, Color(0.88, 0.76, 0.28, 0.95), false, 2.0)
			var label := "Leave" if option.retreats_from_battle else "Attack" if not option.attack_target_id.is_empty() else "%d MP" % option.movement_cost
			draw_string(_ui_font(), rect.position + Vector2(2.0, 20.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0, 11, Color(1.0, 0.94, 0.68))
		else:
			draw_rect(rect, Color(0.10, 0.08, 0.08, 0.52), true)
			draw_rect(rect, Color(0.70, 0.30, 0.26, 0.78), false, 1.0)
			draw_string(_ui_font(), rect.position + Vector2(2.0, 20.0), "—", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0, 12, Color(0.90, 0.62, 0.56))


func _gui_input(event: InputEvent) -> void:
	if interaction.handle_input(event, size, _render_camera_top_left, _render_camera_visible_cells):
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		interaction.handle_mouse_exit()


func _draw_characters(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	var target_ids: Dictionary = {}
	for target: CharacterView in combat.character_targets:
		target_ids[target.id] = true
	for character: CharacterView in _view.party_members:
		if _playback_hides(character.id):
			continue
		var coordinate := _effective_actor_position(combat, character.id)
		if not BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
			continue
		var rect := _playback_actor_rect(character.id, coordinate, camera, draw_origin)
		var asset := _media.asset_by_id(character.combat_icon_id) if _media != null else null
		_draw_actor(rect, _textures.actor_texture(asset), character.name, _actor_is_highlighted(character.id, combat.active_actor_id), target_ids.has(character.id), character.traitor)


func _draw_persistent_fields(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	var atlas_asset := _textures.battle_atlas_asset()
	var atlas_texture := _textures.battle_atlas_texture()
	for field: PersistentCombatFieldView in combat.persistent_fields:
		var tile_id := BattlefieldTextureCache.persistent_field_tile_id(field.queue_icon)
		var region := Rect2i() if atlas_asset == null else atlas_asset.region_for(tile_id)
		for coordinate: Vector2i in field.affected_coordinates:
			if not BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
				continue
			var rect := BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin)
			if atlas_texture != null and region.has_area():
				draw_texture_rect_region(atlas_texture, rect, Rect2(region))
			else:
				draw_rect(rect.grow(-3.0), Color(0.48, 0.22, 0.62, 0.48), true)
				draw_rect(rect.grow(-3.0), Color(0.86, 0.66, 0.98, 0.86), false, 1.0)


func _draw_revealed_relationships(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	if not interaction.reveal_friends:
		return
	var origin := BattlefieldPresentationGeometry.actor_position(combat, _view.party_members, combat.active_actor_id)
	if not BattlefieldPresentationGeometry.coordinate_is_visible(origin, camera, visible_cells):
		return
	var start := BattlefieldPresentationGeometry.cell_rect(origin, camera, draw_origin).get_center()
	for character: CharacterView in _view.party_members:
		var coordinate := combat.battlefield.character_position(character.id)
		if character.id == combat.active_actor_id or not BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
			continue
		var color := Color(0.20, 0.42, 1.0, 0.90) if character.condition_values[ConditionRules.HELPLESS] != 0 else Color(0.18, 0.90, 0.38, 0.86) if combat.friendly_actor_ids.has(character.id) else Color(0.95, 0.22, 0.18, 0.86)
		draw_line(start, BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin).get_center(), color, 2.0)
	for monster: MonsterView in combat.monsters:
		var coordinate := combat.battlefield.monster_position(monster.id)
		if not BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
			continue
		var color := Color(0.20, 0.42, 1.0, 0.90) if monster.helpless else Color(0.18, 0.90, 0.38, 0.86) if combat.friendly_actor_ids.has(monster.id) else Color(0.95, 0.22, 0.18, 0.86)
		draw_line(start, BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin).get_center(), color, 2.0)


func _draw_monsters(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	var target_ids: Dictionary = {}
	for target: MonsterView in combat.targets:
		target_ids[target.id] = true
	for monster: MonsterView in combat.monsters:
		if _playback_hides(monster.id):
			continue
		var footprint := combat.battlefield.monster_footprint(monster.id)
		var source_anchor := combat.battlefield.monster_position(monster.id)
		var effective_anchor := _effective_actor_position(combat, monster.id)
		if source_anchor.x >= 0 and effective_anchor.x >= 0 and source_anchor != effective_anchor:
			var offset := effective_anchor - source_anchor
			for index: int in footprint.size():
				footprint[index] += offset
		var visible_footprint: Array[Vector2i] = []
		for coordinate: Vector2i in footprint:
			if BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
				visible_footprint.append(coordinate)
		if visible_footprint.is_empty():
			continue
		var rect := BattlefieldPresentationGeometry.moving_footprint_rect(visible_footprint, effective_anchor, _playback_frame if _playback_frame != null and _playback_frame.actor_id == monster.id else null, camera, draw_origin)
		var icon_id := BattlefieldPresentationGeometry.classic_monster_icon_id(monster.icon_id, bool(_monster_facing_right.get(monster.id, false)))
		var asset := _media.asset_by_resource(monster.icon_resource_type, icon_id) if _media != null else null
		if _media != null and asset == null and icon_id != monster.icon_id:
			asset = _media.asset_by_resource(monster.icon_resource_type, monster.icon_id)
		_draw_actor(rect, _textures.actor_texture(asset), monster.name, _actor_is_highlighted(monster.id, combat.active_actor_id), target_ids.has(monster.id), monster.traitor)


func _draw_targeting_preview(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	var targeting := interaction.targeting
	if targeting == null:
		return
	if targeting.mode == &"area":
		var center := targeting.selected_coordinate if targeting.selected_coordinate.x >= 0 else targeting.hovered_coordinate
		if center.x < 0:
			return
		var legal := targeting.validation_deferred or targeting.legal_coordinates.has(center)
		var outline := Color(0.96, 0.82, 0.30, 0.96) if legal else Color(0.62, 0.64, 0.68, 0.86)
		for offset: Vector2i in targeting.area_offsets:
			var coordinate := center + offset
			if BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
				draw_rect(BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin).grow(-2.0), outline, false, 2.0)
		return
	if targeting.mode == &"coordinate_sequence":
		for index: int in targeting.selected_coordinates.size():
			var coordinate := targeting.selected_coordinates[index]
			if not BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
				continue
			var rect := BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin)
			draw_rect(rect.grow(-2.0), Color(1.0, 0.86, 0.28, 0.98), false, 3.0)
			draw_string(_ui_font(), rect.position + Vector2(4.0, 18.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, 24.0, 15, Color(1.0, 0.94, 0.72))
		var hovered := targeting.hovered_coordinate
		if hovered.x >= 0 and not targeting.selected_coordinates.has(hovered) and BattlefieldPresentationGeometry.coordinate_is_visible(hovered, camera, visible_cells):
			draw_rect(BattlefieldPresentationGeometry.cell_rect(hovered, camera, draw_origin).grow(-2.0), Color(0.86, 0.80, 0.62, 0.78), false, 2.0)
		return
	for candidate_id: String in targeting.candidate_ids:
		var rect := _combatant_rect(combat, candidate_id, camera, visible_cells, draw_origin)
		if rect.has_area():
			draw_rect(rect.grow(2.0), Color(0.86, 0.80, 0.62, 0.78), false, 2.0)
	for index: int in targeting.selected_ids.size():
		var selected_id := targeting.selected_ids[index]
		var rect := _combatant_rect(combat, selected_id, camera, visible_cells, draw_origin)
		if not rect.has_area():
			continue
		draw_rect(rect.grow(4.0), Color(1.0, 0.86, 0.28, 0.98), false, 4.0)
		if targeting.mode == &"sequence":
			draw_string(_ui_font(), rect.position + Vector2(4.0, 18.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, 24.0, 15, Color(1.0, 0.94, 0.72))


func _draw_playback_overlay(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	if _playback_frame == null:
		return
	var target_rect := _combatant_rect(combat, _playback_frame.target_id, camera, visible_cells, draw_origin)
	var actor_rect := _combatant_rect(combat, _playback_frame.actor_id, camera, visible_cells, draw_origin)
	if not target_rect.has_area() and _playback_frame.to_coordinate.x >= 0 and BattlefieldPresentationGeometry.coordinate_is_visible(_playback_frame.to_coordinate, camera, visible_cells):
		target_rect = BattlefieldPresentationGeometry.cell_rect(_playback_frame.to_coordinate, camera, draw_origin)
	match _playback_frame.kind:
		&"battle_cue":
			_draw_centered_cue(_playback_frame.display_text)
		&"actor_cue":
			if not target_rect.has_area():
				target_rect = actor_rect
			if target_rect.has_area():
				draw_rect(target_rect.grow(4.0), Color(1.0, 0.86, 0.28, 0.95), false, 4.0)
			if not _playback_frame.display_text.is_empty():
				_draw_centered_cue(_playback_frame.display_text)
		&"melee_attack":
			if actor_rect.has_area():
				draw_rect(actor_rect.grow(3.0), Color(1.0, 0.90, 0.58, 0.95), false, 3.0)
			if target_rect.has_area():
				draw_rect(target_rect.grow(2.0), Color(1.0, 0.96, 0.82, 0.95), false, 3.0)
		&"projectile":
			_draw_projectile(actor_rect, target_rect)
		&"spell_projectile":
			_draw_spell_projectile(actor_rect, target_rect)
		&"spell_cast", &"spell_effect":
			_draw_spell_effect(actor_rect, target_rect)
		&"result", &"defeat", &"retreat":
			_draw_result(target_rect if target_rect.has_area() else actor_rect)


func _draw_centered_cue(text: String) -> void:
	if text.is_empty():
		return
	var cue_rect := Rect2(Vector2(size.x * 0.5 - 110.0, HEADER_HEIGHT + 8.0), Vector2(220.0, 34.0))
	draw_rect(cue_rect, Color(0.02, 0.025, 0.03, 0.86), true)
	draw_rect(cue_rect, Color(0.86, 0.72, 0.30, 0.95), false, 2.0)
	draw_string(_ui_font(), cue_rect.position + Vector2(4.0, 23.0), text, HORIZONTAL_ALIGNMENT_CENTER, cue_rect.size.x - 8.0, 16, Color(1.0, 0.90, 0.56))


func _draw_projectile(actor_rect: Rect2, target_rect: Rect2) -> void:
	if not actor_rect.has_area() or not target_rect.has_area():
		return
	var point := actor_rect.get_center().lerp(target_rect.get_center(), _playback_frame.progress)
	draw_circle(point, 5.0, Color(1.0, 0.91, 0.55, 0.98))
	draw_circle(point, 7.0, Color(1.0, 1.0, 0.88, 0.72), false, 2.0)


func _draw_spell_projectile(actor_rect: Rect2, target_rect: Rect2) -> void:
	if not actor_rect.has_area() or not target_rect.has_area():
		return
	var point := actor_rect.get_center().lerp(target_rect.get_center(), _playback_frame.progress)
	var atlas_asset := _textures.battle_atlas_asset()
	var atlas_texture := _textures.battle_atlas_texture()
	var region := Rect2i() if atlas_asset == null else atlas_asset.region_for(_playback_frame.battle_tile_id)
	if _playback_frame.battle_tile_id <= 0 or atlas_texture == null or region.size.x <= 0 or region.size.y <= 0:
		last_playback_media_diagnostic = {"resourceType": "PICT", "resourceId": 302, "tileId": _playback_frame.battle_tile_id, "decodeResult": "unavailable", "role": "classic-combat-spell-projectile"}
		draw_circle(point, 6.0, Color(0.82, 0.72, 1.0, 0.96))
		return
	last_playback_media_diagnostic = {"resourceType": "PICT", "resourceId": 302, "tileId": _playback_frame.battle_tile_id, "assetId": atlas_asset.id, "decodeResult": "decoded", "role": "classic-combat-spell-projectile"}
	var projectile_rect := Rect2(point - Vector2(16.0, 16.0), Vector2(32.0, 32.0))
	draw_texture_rect_region(atlas_texture, projectile_rect, Rect2(region))


func _draw_spell_effect(actor_rect: Rect2, target_rect: Rect2) -> void:
	var destination := target_rect if target_rect.has_area() else actor_rect
	if not destination.has_area():
		return
	_draw_classic_effect(destination, "classic-combat-effect")


func _draw_classic_effect(destination: Rect2, role: String) -> void:
	if _playback_frame.effect_resource_id <= 0 or _media == null:
		last_playback_media_diagnostic = {"resourceType": "cicn", "resourceId": _playback_frame.effect_resource_id, "decodeResult": "unavailable", "role": role}
		draw_rect(destination.grow(4.0), Color(0.82, 0.72, 1.0, 0.90), false, 3.0)
		return
	var asset := _media.asset_by_resource(_playback_frame.effect_resource_type, _playback_frame.effect_resource_id)
	var texture := _textures.effect_texture(asset)
	last_playback_media_diagnostic = _media.resolution_diagnostic(_playback_frame.effect_resource_type, _playback_frame.effect_resource_id, role, "decoded" if texture != null else "decode-failed")
	if texture == null:
		draw_rect(destination.grow(4.0), Color(0.82, 0.72, 1.0, 0.90), false, 3.0)
		return
	var effect_size := Vector2(texture.get_size())
	var effect_rect := Rect2(destination.get_center() - effect_size * 0.5, effect_size)
	draw_texture_rect(texture, effect_rect, false)


func _draw_result(target_rect: Rect2) -> void:
	if not target_rect.has_area() or _playback_frame.display_text.is_empty():
		return
	if _playback_frame.effect_resource_id > 0:
		_draw_classic_effect(target_rect, "classic-combat-result")
	var text_color := Color(0.72, 1.0, 0.72) if _playback_frame.result_kind == &"healing" else Color(1.0, 0.95, 0.82)
	var result_rect := Rect2(target_rect.get_center() - Vector2(18.0, 14.0), Vector2(36.0, 28.0))
	if _playback_frame.effect_resource_id <= 0:
		draw_rect(result_rect, Color(0.02, 0.02, 0.02, 0.76), true)
	draw_string(_ui_font(), result_rect.position + Vector2(1.0, 20.0), _playback_frame.display_text, HORIZONTAL_ALIGNMENT_CENTER, result_rect.size.x - 2.0, 14, text_color)


func _effective_actor_position(combat: CombatView, actor_id: String) -> Vector2i:
	if _playback_frame != null:
		var playback_position := _playback_frame.position_for(actor_id)
		if playback_position.x >= 0:
			return playback_position
	return BattlefieldPresentationGeometry.actor_position(combat, _view.party_members, actor_id)


func _playback_hides(actor_id: String) -> bool:
	return _playback_frame != null and _playback_frame.hides(actor_id)


func _actor_is_highlighted(actor_id: String, active_actor_id: String) -> bool:
	return actor_id == active_actor_id or _playback_frame != null and _playback_frame.kind == &"actor_cue" and _playback_frame.actor_id == actor_id


func _playback_actor_rect(actor_id: String, coordinate: Vector2i, camera: Vector2i, draw_origin: Vector2) -> Rect2:
	var rect := BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin)
	if _playback_frame != null and _playback_frame.actor_id == actor_id and _playback_frame.kind == &"move_start":
		rect.position = BattlefieldPresentationGeometry.interpolated_draw_position(_playback_frame, camera, draw_origin)
	return rect


func _sync_monster_facings() -> void:
	if _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		_monster_facing_right.clear()
		return
	var combat := _view.combat_view
	var party_reference := combat.battlefield.party_anchor
	for character: CharacterView in _view.party_members:
		var coordinate := combat.battlefield.character_position(character.id)
		if coordinate.x >= 0:
			party_reference = coordinate
			break
	var active_ids: Dictionary = {}
	for monster: MonsterView in combat.monsters:
		active_ids[monster.id] = true
		if not _monster_facing_right.has(monster.id):
			_monster_facing_right[monster.id] = combat.battlefield.monster_position(monster.id).x < party_reference.x
	for actor_id: Variant in _monster_facing_right.keys():
		if not active_ids.has(actor_id):
			_monster_facing_right.erase(actor_id)


func _combatant_rect(combat: CombatView, actor_id: String, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> Rect2:
	if actor_id.is_empty() or _playback_hides(actor_id):
		return Rect2()
	var coordinate := _effective_actor_position(combat, actor_id)
	if not BattlefieldPresentationGeometry.coordinate_is_visible(coordinate, camera, visible_cells):
		return Rect2()
	for monster: MonsterView in combat.monsters:
		if monster.id != actor_id:
			continue
		var footprint := combat.battlefield.monster_footprint(actor_id)
		var source_anchor := combat.battlefield.monster_position(actor_id)
		var offset := coordinate - source_anchor
		for index: int in footprint.size():
			footprint[index] += offset
		return BattlefieldPresentationGeometry.footprint_rect(footprint, camera, draw_origin)
	return _playback_actor_rect(actor_id, coordinate, camera, draw_origin)


func _draw_actor(rect: Rect2, texture: Texture2D, label: String, active: bool, target: bool, hostile: bool) -> void:
	if texture != null:
		draw_texture_rect(texture, rect, false)
	else:
		draw_rect(rect.grow(-3.0), Color(0.62, 0.20, 0.18) if hostile else Color(0.18, 0.42, 0.64), true)
		draw_string(_ui_font(), rect.position + Vector2(5.0, 20.0), label.left(2).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color.WHITE)
	if target:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.35, 0.26), false, 3.0)
	if active:
		draw_rect(rect.grow(2.0), Color(0.98, 0.82, 0.25), false, 3.0)


func _ui_font() -> Font:
	return get_theme_font(&"font", &"Label")
