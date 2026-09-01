class_name ClassicBattlefieldPresenter
extends Control

const PersistentCombatFieldViewType := preload("res://src/core/view/persistent_combat_field_view.gd")

signal combat_body_submitted(body: InteractionResponse.CombatBody)
signal combatant_inspected(combatant_id: String)
signal targeting_changed(selection: CombatTargetingState)
signal targeting_cancelled

const NATIVE_CELL_SIZE: float = 32.0
const HEADER_HEIGHT: float = 38.0
const SURROUND_TEXTURE_PATH := "res://src/presentation/assets/ui/classic-exploration-surround-tile.png"

var _view: GameView
var _media: ClassicMediaCatalog
var _atlas_asset: MediaAsset
var _atlas_texture: Texture2D
var _upper_atlas_id: String = ""
var _upper_atlas_asset: MediaAsset
var _upper_atlas_texture: Texture2D
var _actor_textures: Dictionary = {}
var _movement_costs_visible: bool = false
var _hovered_coordinate := Vector2i(-1, -1)
var _camera_focus_id: String = ""
var _render_camera_top_left := Vector2i(-1, -1)
var _render_camera_focus_id: String = ""
var _render_camera_visible_cells := Vector2i.ZERO
var _last_active_actor_id: String = ""
var _reveal_friends: bool = false
var _playback_frame: CombatPlaybackFrame
var _monster_facing_right: Dictionary = {}
var last_playback_media_diagnostic: Dictionary = {}
var _targeting: CombatTargetingState
var _surround_texture: Texture2D = load(SURROUND_TEXTURE_PATH) as Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func present(game_view: GameView) -> void:
	var next_active_actor_id := ""
	if game_view != null and game_view.combat_view != null:
		next_active_actor_id = game_view.combat_view.active_actor_id
	if next_active_actor_id != _last_active_actor_id:
		_camera_focus_id = ""
		_render_camera_focus_id = ""
	_last_active_actor_id = next_active_actor_id
	_view = game_view
	_playback_frame = null
	_sync_monster_facings()
	if _view != null and _view.combat_view != null and _media != null and _atlas_texture == null:
		_atlas_asset = _media.battle_tileset()
		_atlas_texture = _load_image_texture(_atlas_asset)
	if _view == null or _view.combat_view == null:
		_movement_costs_visible = false
		_hovered_coordinate = Vector2i(-1, -1)
		_camera_focus_id = ""
		_render_camera_top_left = Vector2i(-1, -1)
		_render_camera_focus_id = ""
		_render_camera_visible_cells = Vector2i.ZERO
		_last_active_actor_id = ""
		_reveal_friends = false
	elif not _camera_focus_id.is_empty() and actor_position(_view.combat_view, _view.party_members, _camera_focus_id).x < 0:
		_camera_focus_id = ""
	var requested_upper_atlas_id := ""
	if _view != null and _view.combat_view != null and _view.combat_view.battlefield != null:
		requested_upper_atlas_id = _view.combat_view.battlefield.upper_tileset_id
	if requested_upper_atlas_id != _upper_atlas_id:
		_upper_atlas_id = requested_upper_atlas_id
		_upper_atlas_asset = _media.tileset_by_id(_upper_atlas_id) if _media != null and not _upper_atlas_id.is_empty() else null
		_upper_atlas_texture = _load_image_texture(_upper_atlas_asset)
	queue_redraw()


func present_playback_frame(frame: CombatPlaybackFrame) -> void:
	if _playback_frame == null and frame != null:
		_camera_focus_id = ""
	if frame != _playback_frame and frame != null and frame.kind == &"actor_cue":
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
	_atlas_asset = null
	_atlas_texture = null
	_upper_atlas_id = ""
	_upper_atlas_asset = null
	_upper_atlas_texture = null
	_actor_textures.clear()
	queue_redraw()


func has_battle_artwork() -> bool:
	if _atlas_asset == null or _atlas_texture == null:
		return false
	if _upper_atlas_id.is_empty():
		return true
	return _upper_atlas_asset != null and _upper_atlas_texture != null


func _draw() -> void:
	if _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		return
	_draw_battle_stage()
	var combat := _view.combat_view
	var battlefield := combat.battlefield
	var focus_id := camera_focus_id_for(_playback_frame, _camera_focus_id, combat.active_actor_id)
	var active_position := _effective_actor_position(combat, focus_id)
	if active_position.x < 0:
		active_position = battlefield.party_anchor
	var visible_cells := viewport_cells_for(size)
	var camera := tracked_camera_top_left(
		_render_camera_top_left,
		active_position,
		visible_cells,
		_render_camera_focus_id != focus_id or _render_camera_visible_cells != visible_cells
	)
	_render_camera_top_left = camera
	_render_camera_focus_id = focus_id
	_render_camera_visible_cells = visible_cells
	var draw_origin := battlefield_draw_origin(size, visible_cells)
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
	var current_actor_name := actor_name(combat, _view.party_members, combat.active_actor_id)
	var title := "Battle %s • Round %d • %s" % [combat.battle_id, combat.round_number, current_actor_name]
	var facts := "%d attack%s • %d movement • %s" % [combat.attack_units_remaining, "" if combat.attack_units_remaining == 1 else "s", combat.movement_remaining, String(combat.weapon_mode).capitalize()]
	draw_string(_ui_font(), Vector2(8.0, 17.0), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 250.0, 120.0), 16, Color(0.86, 0.75, 0.42))
	draw_string(_ui_font(), Vector2(size.x - 242.0, 17.0), facts, HORIZONTAL_ALIGNMENT_RIGHT, 234.0, 12, Color(0.73, 0.76, 0.80))


func _draw_tactical_legend() -> void:
	if _reveal_friends:
		var x := 8.0
		for entry: Array in [["Hostile", Color(0.95, 0.22, 0.18)], ["Friendly", Color(0.18, 0.90, 0.38)], ["Helpless", Color(0.20, 0.42, 1.0)]]:
			draw_line(Vector2(x, 29.0), Vector2(x + 18.0, 29.0), entry[1], 2.0)
			draw_string(_ui_font(), Vector2(x + 23.0, 33.0), String(entry[0]), HORIZONTAL_ALIGNMENT_LEFT, 58.0, 10, Color(0.82, 0.84, 0.84))
			x += 86.0
		draw_string(_ui_font(), Vector2(x, 33.0), "Click board to dismiss", HORIZONTAL_ALIGNMENT_LEFT, 126.0, 10, Color(0.63, 0.67, 0.69))
	elif _movement_costs_visible:
		draw_string(_ui_font(), Vector2(8.0, 33.0), "Movement cost aid • release Shift to hide", HORIZONTAL_ALIGNMENT_LEFT, 250.0, 10, Color(0.94, 0.82, 0.38))


func _draw_terrain_cell(tile_id: int, rect: Rect2) -> void:
	var uses_landlook := tile_id <= 200 and not _upper_atlas_id.is_empty()
	var asset := _upper_atlas_asset if uses_landlook else _atlas_asset
	var texture := _upper_atlas_texture if uses_landlook else _atlas_texture
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
		if not coordinate_is_visible(option.destination, camera, visible_cells):
			continue
		if not _movement_costs_visible and option.destination != _hovered_coordinate:
			continue
		var rect := cell_rect(option.destination, camera, draw_origin).grow(-2.0)
		if option.enabled:
			draw_rect(rect, Color(0.08, 0.10, 0.08, 0.62), true)
			draw_rect(rect, Color(0.88, 0.76, 0.28, 0.95), false, 2.0)
			var label := "Leave" if option.retreats_from_battle else "Attack" if not option.attack_target_id.is_empty() else "%d MP" % option.movement_cost
			draw_string(_ui_font(), rect.position + Vector2(2.0, 20.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0, 11, Color(1.0, 0.94, 0.68))
		else:
			draw_rect(rect, Color(0.10, 0.08, 0.08, 0.52), true)
			draw_rect(rect, Color(0.70, 0.30, 0.26, 0.78), false, 1.0)
			draw_string(_ui_font(), rect.position + Vector2(2.0, 20.0), "—", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0, 12, Color(0.90, 0.62, 0.56))


func set_movement_costs_visible(visible_costs: bool) -> void:
	if _movement_costs_visible == visible_costs:
		return
	_movement_costs_visible = visible_costs
	queue_redraw()


func movement_costs_visible() -> bool:
	return _movement_costs_visible


func focus_combatant(combatant_id: String) -> void:
	_camera_focus_id = combatant_id
	_render_camera_focus_id = ""
	queue_redraw()


func toggle_reveal_friends() -> void:
	_reveal_friends = not _reveal_friends
	queue_redraw()


func dismiss_reveal_friends() -> bool:
	if not _reveal_friends:
		return false
	_reveal_friends = false
	queue_redraw()
	return true


func reveal_friends_visible() -> bool:
	return _reveal_friends


func submit_movement_direction(direction: Vector2i) -> bool:
	if _playback_frame != null or _targeting != null:
		return false
	var option := _movement_option_for_direction(direction)
	return _submit_movement_option(option)


func _gui_input(event: InputEvent) -> void:
	if _playback_frame != null or _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		return
	if _targeting != null:
		_handle_targeting_input(event)
		return
	if event is InputEventMouseMotion:
		var hover_option := _movement_option_toward_local_position((event as InputEventMouseMotion).position)
		var next_hover := hover_option.destination if hover_option != null else Vector2i(-1, -1)
		if next_hover != _hovered_coordinate:
			_hovered_coordinate = next_hover
			queue_redraw()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
		if dismiss_reveal_friends():
			accept_event()
			return
		if (event as InputEventMouseButton).ctrl_pressed or (event as InputEventMouseButton).meta_pressed:
			var inspected_id := combatant_at(_view.combat_view, _view.party_members, _coordinate_at_local_position((event as InputEventMouseButton).position))
			if not inspected_id.is_empty():
				focus_combatant(inspected_id)
				combatant_inspected.emit(inspected_id)
				accept_event()
			return
		if _submit_movement_option(_movement_option_toward_local_position((event as InputEventMouseButton).position)):
			accept_event()


func _notification(what: int) -> void:
	if what != NOTIFICATION_MOUSE_EXIT:
		return
	var changed := false
	if _hovered_coordinate != Vector2i(-1, -1):
		_hovered_coordinate = Vector2i(-1, -1)
		changed = true
	if _targeting != null and _targeting.selected_coordinate.x < 0 and _targeting.hovered_coordinate != Vector2i(-1, -1):
		_targeting.hovered_coordinate = Vector2i(-1, -1)
		changed = true
	if changed:
		queue_redraw()


func begin_targeting(configuration: CombatTargetingRequest) -> bool:
	if _playback_frame != null or _view == null or _view.combat_view == null:
		return false
	if configuration == null or not configuration.is_valid():
		return false
	_targeting = CombatTargetingState.new(configuration)
	_reveal_friends = false
	targeting_changed.emit(_targeting)
	queue_redraw()
	return true


func confirm_targeting() -> bool:
	if _targeting == null:
		return false
	var body := _targeting.committed_body()
	if body == null:
		targeting_changed.emit(_targeting)
		return false
	_targeting = null
	queue_redraw()
	combat_body_submitted.emit(body)
	return true


func cancel_targeting() -> bool:
	if _targeting == null:
		return false
	_targeting = null
	queue_redraw()
	targeting_cancelled.emit()
	return true


func targeting_active() -> bool:
	return _targeting != null


func target_with_keyboard() -> bool:
	if _targeting == null or not _targeting.target_with_keyboard():
		return false
	if not _targeting.selected_ids.is_empty():
		_camera_focus_id = _targeting.selected_ids[-1]
	targeting_changed.emit(_targeting)
	queue_redraw()
	return true


func rotate_targeting() -> bool:
	if _targeting == null or not _targeting.rotate_area():
		return false
	targeting_changed.emit(_targeting)
	queue_redraw()
	return true


func _handle_targeting_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_targeting.hovered_coordinate = _coordinate_at_local_position((event as InputEventMouseMotion).position)
		queue_redraw()
		return
	if not event is InputEventMouseButton or not (event as InputEventMouseButton).pressed:
		return
	if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		cancel_targeting()
		accept_event()
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var coordinate := _coordinate_at_local_position((event as InputEventMouseButton).position)
	if coordinate.x < 0:
		return
	if _targeting.mode in [&"area", &"coordinate_sequence"]:
		_targeting.select_coordinate(coordinate)
	else:
		var combatant_id := combatant_at(_view.combat_view, _view.party_members, coordinate)
		_targeting.select_combatant(combatant_id)
	targeting_changed.emit(_targeting)
	queue_redraw()
	accept_event()


func _coordinate_at_local_position(local_position: Vector2) -> Vector2i:
	var combat := _view.combat_view
	var battlefield := combat.battlefield
	var active_position := actor_position(combat, _view.party_members, combat.active_actor_id)
	if active_position.x < 0:
		active_position = battlefield.party_anchor
	var visible_cells := viewport_cells_for(size)
	var camera := _camera_for_input(active_position, visible_cells)
	return coordinate_for_point(local_position, camera, visible_cells, size)


func _movement_option_for_direction(direction: Vector2i) -> CombatMoveOptionView:
	if _view == null or _view.combat_view == null:
		return null
	for option: CombatMoveOptionView in _view.combat_view.movement_options:
		if option.direction == direction:
			return option
	return null


func _movement_option_for_destination(destination: Vector2i) -> CombatMoveOptionView:
	if _view == null or _view.combat_view == null:
		return null
	for option: CombatMoveOptionView in _view.combat_view.movement_options:
		if option.destination == destination:
			return option
	return null


func _movement_option_toward_local_position(local_position: Vector2) -> CombatMoveOptionView:
	if _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		return null
	var origin := actor_position(_view.combat_view, _view.party_members, _view.combat_view.active_actor_id)
	var visible_cells := viewport_cells_for(size)
	var camera := _camera_for_input(origin, visible_cells)
	var draw_origin := battlefield_draw_origin(size, visible_cells)
	return _movement_option_for_direction(click_direction_for_point(cell_rect(origin, camera, draw_origin), local_position))


func _camera_for_input(fallback_focus: Vector2i, visible_cells: Vector2i) -> Vector2i:
	if _render_camera_top_left.x >= 0 and _render_camera_visible_cells == visible_cells:
		return _render_camera_top_left
	return camera_top_left(fallback_focus, visible_cells)


func _submit_movement_option(option: CombatMoveOptionView) -> bool:
	if option == null or not option.enabled or _view == null or _view.combat_view == null:
		return false
	var body := InteractionResponse.CombatBody.new(&"retreat_edge" if option.retreats_from_battle else &"move", _view.combat_view.active_actor_id)
	body.destination = option.destination
	body.has_destination = true
	combat_body_submitted.emit(body)
	return true


func _draw_characters(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	var target_ids: Dictionary = {}
	for target: CharacterView in combat.character_targets:
		target_ids[target.id] = true
	for character: CharacterView in _view.party_members:
		if _playback_hides(character.id):
			continue
		var coordinate := _effective_actor_position(combat, character.id)
		if not coordinate_is_visible(coordinate, camera, visible_cells):
			continue
		var rect := _playback_actor_rect(character.id, coordinate, camera, draw_origin)
		var asset := _media.asset_by_id(character.combat_icon_id) if _media != null else null
		_draw_actor(rect, _texture_for(asset), character.name, _actor_is_highlighted(character.id, combat.active_actor_id), target_ids.has(character.id), character.traitor)


func _draw_persistent_fields(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	for field: PersistentCombatFieldViewType in combat.persistent_fields:
		var tile_id := persistent_field_tile_id(field.queue_icon)
		var region := Rect2i() if _atlas_asset == null else _atlas_asset.region_for(tile_id)
		for coordinate: Vector2i in field.affected_coordinates:
			if not coordinate_is_visible(coordinate, camera, visible_cells):
				continue
			var rect := cell_rect(coordinate, camera, draw_origin)
			if _atlas_texture != null and region.has_area():
				draw_texture_rect_region(_atlas_texture, rect, Rect2(region))
			else:
				draw_rect(rect.grow(-3.0), Color(0.48, 0.22, 0.62, 0.48), true)
				draw_rect(rect.grow(-3.0), Color(0.86, 0.66, 0.98, 0.86), false, 1.0)


static func persistent_field_tile_id(queue_icon: int) -> int:
	return 200 + queue_icon


func _draw_revealed_relationships(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	if not _reveal_friends:
		return
	var origin := actor_position(combat, _view.party_members, combat.active_actor_id)
	if not coordinate_is_visible(origin, camera, visible_cells):
		return
	var start := cell_rect(origin, camera, draw_origin).get_center()
	for character: CharacterView in _view.party_members:
		var coordinate := combat.battlefield.character_position(character.id)
		if character.id == combat.active_actor_id or not coordinate_is_visible(coordinate, camera, visible_cells):
			continue
		var color := Color(0.20, 0.42, 1.0, 0.90) if character.condition_values[ConditionRules.HELPLESS] != 0 else Color(0.18, 0.90, 0.38, 0.86) if combat.friendly_actor_ids.has(character.id) else Color(0.95, 0.22, 0.18, 0.86)
		draw_line(start, cell_rect(coordinate, camera, draw_origin).get_center(), color, 2.0)
	for monster: MonsterView in combat.monsters:
		var coordinate := combat.battlefield.monster_position(monster.id)
		if not coordinate_is_visible(coordinate, camera, visible_cells):
			continue
		var color := Color(0.20, 0.42, 1.0, 0.90) if monster.helpless else Color(0.18, 0.90, 0.38, 0.86) if combat.friendly_actor_ids.has(monster.id) else Color(0.95, 0.22, 0.18, 0.86)
		draw_line(start, cell_rect(coordinate, camera, draw_origin).get_center(), color, 2.0)


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
			if coordinate_is_visible(coordinate, camera, visible_cells):
				visible_footprint.append(coordinate)
		if visible_footprint.is_empty():
			continue
		var rect := moving_footprint_rect(visible_footprint, effective_anchor, _playback_frame if _playback_frame != null and _playback_frame.actor_id == monster.id else null, camera, draw_origin)
		var icon_id := classic_monster_icon_id(monster.icon_id, bool(_monster_facing_right.get(monster.id, false)))
		var asset := _media.asset_by_resource(monster.icon_resource_type, icon_id) if _media != null else null
		if _media != null and asset == null and icon_id != monster.icon_id:
			asset = _media.asset_by_resource(monster.icon_resource_type, monster.icon_id)
		_draw_actor(rect, _texture_for(asset), monster.name, _actor_is_highlighted(monster.id, combat.active_actor_id), target_ids.has(monster.id), monster.traitor)


func _draw_targeting_preview(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	if _targeting == null:
		return
	if _targeting.mode == &"area":
		var center := _targeting.selected_coordinate if _targeting.selected_coordinate.x >= 0 else _targeting.hovered_coordinate
		if center.x < 0:
			return
		var legal := _targeting.validation_deferred or _targeting.legal_coordinates.has(center)
		var outline := Color(0.96, 0.82, 0.30, 0.96) if legal else Color(0.62, 0.64, 0.68, 0.86)
		for offset: Vector2i in _targeting.area_offsets:
			var coordinate := center + offset
			if coordinate_is_visible(coordinate, camera, visible_cells):
				draw_rect(cell_rect(coordinate, camera, draw_origin).grow(-2.0), outline, false, 2.0)
		return
	if _targeting.mode == &"coordinate_sequence":
		for index: int in _targeting.selected_coordinates.size():
			var coordinate := _targeting.selected_coordinates[index]
			if not coordinate_is_visible(coordinate, camera, visible_cells):
				continue
			var rect := cell_rect(coordinate, camera, draw_origin)
			draw_rect(rect.grow(-2.0), Color(1.0, 0.86, 0.28, 0.98), false, 3.0)
			draw_string(_ui_font(), rect.position + Vector2(4.0, 18.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, 24.0, 15, Color(1.0, 0.94, 0.72))
		var hovered := _targeting.hovered_coordinate
		if hovered.x >= 0 and not _targeting.selected_coordinates.has(hovered) and coordinate_is_visible(hovered, camera, visible_cells):
			draw_rect(cell_rect(hovered, camera, draw_origin).grow(-2.0), Color(0.86, 0.80, 0.62, 0.78), false, 2.0)
		return
	for candidate_id: String in _targeting.candidate_ids:
		var rect := _combatant_rect(combat, candidate_id, camera, visible_cells, draw_origin)
		if rect.has_area():
			draw_rect(rect.grow(2.0), Color(0.86, 0.80, 0.62, 0.78), false, 2.0)
	for index: int in _targeting.selected_ids.size():
		var selected_id := _targeting.selected_ids[index]
		var rect := _combatant_rect(combat, selected_id, camera, visible_cells, draw_origin)
		if not rect.has_area():
			continue
		draw_rect(rect.grow(4.0), Color(1.0, 0.86, 0.28, 0.98), false, 4.0)
		if _targeting.mode == &"sequence":
			draw_string(_ui_font(), rect.position + Vector2(4.0, 18.0), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, 24.0, 15, Color(1.0, 0.94, 0.72))


func _draw_playback_overlay(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	if _playback_frame == null:
		return
	var target_rect := _combatant_rect(combat, _playback_frame.target_id, camera, visible_cells, draw_origin)
	var actor_rect := _combatant_rect(combat, _playback_frame.actor_id, camera, visible_cells, draw_origin)
	if not target_rect.has_area() and _playback_frame.to_coordinate.x >= 0 and coordinate_is_visible(_playback_frame.to_coordinate, camera, visible_cells):
		target_rect = cell_rect(_playback_frame.to_coordinate, camera, draw_origin)
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
	var region := Rect2i() if _atlas_asset == null else _atlas_asset.region_for(_playback_frame.battle_tile_id)
	if _playback_frame.battle_tile_id <= 0 or _atlas_texture == null or region.size.x <= 0 or region.size.y <= 0:
		last_playback_media_diagnostic = {"resourceType": "PICT", "resourceId": 302, "tileId": _playback_frame.battle_tile_id, "decodeResult": "unavailable", "role": "classic-combat-spell-projectile"}
		draw_circle(point, 6.0, Color(0.82, 0.72, 1.0, 0.96))
		return
	last_playback_media_diagnostic = {"resourceType": "PICT", "resourceId": 302, "tileId": _playback_frame.battle_tile_id, "assetId": _atlas_asset.id, "decodeResult": "decoded", "role": "classic-combat-spell-projectile"}
	var projectile_rect := Rect2(point - Vector2(16.0, 16.0), Vector2(32.0, 32.0))
	draw_texture_rect_region(_atlas_texture, projectile_rect, Rect2(region))


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
	var texture := _effect_texture_for(asset)
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
	return actor_position(combat, _view.party_members, actor_id)


func _playback_hides(actor_id: String) -> bool:
	return _playback_frame != null and _playback_frame.hides(actor_id)


func _actor_is_highlighted(actor_id: String, active_actor_id: String) -> bool:
	return actor_id == active_actor_id or _playback_frame != null and _playback_frame.kind == &"actor_cue" and _playback_frame.actor_id == actor_id


func _playback_actor_rect(actor_id: String, coordinate: Vector2i, camera: Vector2i, draw_origin: Vector2) -> Rect2:
	var rect := cell_rect(coordinate, camera, draw_origin)
	if _playback_frame != null and _playback_frame.actor_id == actor_id and _playback_frame.kind == &"move_start":
		rect.position = _interpolated_draw_position(_playback_frame, camera, draw_origin)
	return rect


static func _interpolated_draw_position(frame: CombatPlaybackFrame, camera: Vector2i, draw_origin: Vector2) -> Vector2:
	var from_position := draw_origin + Vector2(frame.from_coordinate - camera) * NATIVE_CELL_SIZE
	var to_position := draw_origin + Vector2(frame.to_coordinate - camera) * NATIVE_CELL_SIZE
	return from_position.lerp(to_position, frame.progress)


static func moving_footprint_rect(footprint: Array[Vector2i], footprint_anchor: Vector2i, frame: CombatPlaybackFrame, camera: Vector2i, draw_origin: Vector2) -> Rect2:
	var rect := footprint_rect(footprint, camera, draw_origin)
	if not rect.has_area() or frame == null or frame.kind != &"move_start":
		return rect
	var anchor_position := cell_rect(footprint_anchor, camera, draw_origin).position
	rect.position += _interpolated_draw_position(frame, camera, draw_origin) - anchor_position
	return rect


static func classic_monster_icon_id(base_icon_id: int, facing_right: bool) -> int:
	return base_icon_id + 308 if facing_right else base_icon_id


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
	if not coordinate_is_visible(coordinate, camera, visible_cells):
		return Rect2()
	for monster: MonsterView in combat.monsters:
		if monster.id != actor_id:
			continue
		var footprint := combat.battlefield.monster_footprint(actor_id)
		var source_anchor := combat.battlefield.monster_position(actor_id)
		var offset := coordinate - source_anchor
		for index: int in footprint.size():
			footprint[index] += offset
		return footprint_rect(footprint, camera, draw_origin)
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


func _texture_for(asset: MediaAsset) -> Texture2D:
	if asset == null:
		return null
	if _actor_textures.has(asset.id):
		return _actor_textures[asset.id] as Texture2D
	var texture := _load_image_texture(asset)
	_actor_textures[asset.id] = texture
	return texture


func _effect_texture_for(asset: MediaAsset) -> Texture2D:
	if asset == null:
		return null
	var cache_key := "effect:%s" % asset.id
	if _actor_textures.has(cache_key):
		return _actor_textures[cache_key] as Texture2D
	var texture := remove_opaque_white_matte(_load_image_texture(asset))
	_actor_textures[cache_key] = texture
	return texture


static func remove_opaque_white_matte(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var seeds: Array[Vector2i] = [Vector2i.ZERO, Vector2i(width - 1, 0), Vector2i(0, height - 1), Vector2i(width - 1, height - 1)]
	if not seeds.any(func(point: Vector2i) -> bool: return _is_opaque_white(image.get_pixelv(point))):
		return texture
	var visited := PackedByteArray()
	visited.resize(width * height)
	var pending: Array[Vector2i] = seeds
	while not pending.is_empty():
		var point: Vector2i = pending.pop_back()
		var index: int = point.y * width + point.x
		if visited[index] != 0:
			continue
		visited[index] = 1
		var color := image.get_pixelv(point)
		if not _is_opaque_white(color):
			continue
		image.set_pixelv(point, Color(color.r, color.g, color.b, 0.0))
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = point + direction
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < width and neighbor.y < height:
				pending.append(neighbor)
	return ImageTexture.create_from_image(image)


static func _is_opaque_white(color: Color) -> bool:
	return color.a > 0.98 and color.r > 0.92 and color.g > 0.92 and color.b > 0.92


func _load_image_texture(asset: MediaAsset) -> Texture2D:
	return _media.image_texture(asset) if _media != null else null


static func actor_position(combat: CombatView, party_members: Array[CharacterView], actor_id: String) -> Vector2i:
	if combat == null or combat.battlefield == null or actor_id.is_empty():
		return Vector2i(-1, -1)
	for character: CharacterView in party_members:
		if character.id == actor_id:
			return combat.battlefield.character_position(actor_id)
	return combat.battlefield.monster_position(actor_id)


static func actor_name(combat: CombatView, party_members: Array[CharacterView], actor_id: String) -> String:
	for character: CharacterView in party_members:
		if character.id == actor_id:
			return character.name
	if combat != null:
		for monster: MonsterView in combat.monsters:
			if monster.id == actor_id:
				return monster.name
	return actor_id if not actor_id.is_empty() else "Waiting"


static func combatant_at(combat: CombatView, party_members: Array[CharacterView], coordinate: Vector2i) -> String:
	if combat == null or combat.battlefield == null:
		return ""
	for character: CharacterView in party_members:
		if combat.battlefield.character_position(character.id) == coordinate:
			return character.id
	for monster: MonsterView in combat.monsters:
		if combat.battlefield.monster_footprint(monster.id).has(coordinate):
			return monster.id
	return ""


static func click_direction(origin: Vector2i, destination: Vector2i) -> Vector2i:
	var offset := destination - origin
	return Vector2i(signi(offset.x), signi(offset.y))


func _ui_font() -> Font:
	return get_theme_font(&"font", &"Label")


static func click_direction_for_point(active_cell: Rect2, point: Vector2) -> Vector2i:
	var offset := point - active_cell.get_center()
	if offset.length_squared() <= 36.0:
		return Vector2i.ZERO
	var horizontal := absf(offset.x)
	var vertical := absf(offset.y)
	if horizontal > vertical * 2.41421356:
		return Vector2i(signi(roundi(offset.x)), 0)
	if vertical > horizontal * 2.41421356:
		return Vector2i(0, signi(roundi(offset.y)))
	return Vector2i(signi(roundi(offset.x)), signi(roundi(offset.y)))


static func _array_coordinate(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-100_000, -100_000)


static func viewport_cells_for(control_size: Vector2) -> Vector2i:
	return Vector2i(
		mini(BattlefieldState.SIZE, maxi(1, floori(control_size.x / NATIVE_CELL_SIZE))),
		mini(BattlefieldState.SIZE, maxi(1, floori((control_size.y - HEADER_HEIGHT) / NATIVE_CELL_SIZE)))
	)


static func camera_top_left(active_position: Vector2i, visible_cells: Vector2i) -> Vector2i:
	var maximum := Vector2i(BattlefieldState.SIZE, BattlefieldState.SIZE) - visible_cells
	return Vector2i(
		clampi(active_position.x - floori(float(visible_cells.x) / 2.0), 0, maximum.x),
		clampi(active_position.y - floori(float(visible_cells.y) / 2.0), 0, maximum.y)
	)


static func camera_focus_id_for(frame: CombatPlaybackFrame, inspected_focus_id: String, active_actor_id: String) -> String:
	if frame != null and not frame.camera_focus_id.is_empty():
		return frame.camera_focus_id
	if not inspected_focus_id.is_empty():
		return inspected_focus_id
	return active_actor_id


static func tracked_camera_top_left(current_camera: Vector2i, focus_position: Vector2i, visible_cells: Vector2i, force_recenter: bool = false) -> Vector2i:
	if force_recenter or current_camera.x < 0 or not coordinate_is_visible(focus_position, current_camera, visible_cells) or coordinate_is_at_viewport_edge(focus_position, current_camera, visible_cells):
		return camera_top_left(focus_position, visible_cells)
	return current_camera


static func coordinate_is_at_viewport_edge(coordinate: Vector2i, camera: Vector2i, visible_cells: Vector2i) -> bool:
	return coordinate.x <= camera.x or coordinate.y <= camera.y or coordinate.x >= camera.x + visible_cells.x - 1 or coordinate.y >= camera.y + visible_cells.y - 1


static func battlefield_draw_origin(control_size: Vector2, visible_cells: Vector2i) -> Vector2:
	var pixel_size := Vector2(visible_cells) * NATIVE_CELL_SIZE
	return Vector2(
		floorf((control_size.x - pixel_size.x) * 0.5),
		HEADER_HEIGHT + floorf(maxf(control_size.y - HEADER_HEIGHT - pixel_size.y, 0.0) * 0.5)
	)


static func coordinate_for_point(local_position: Vector2, camera: Vector2i, visible_cells: Vector2i, control_size: Vector2) -> Vector2i:
	var relative := local_position - battlefield_draw_origin(control_size, visible_cells)
	if relative.x < 0.0 or relative.y < 0.0:
		return Vector2i(-1, -1)
	var cell := Vector2i(floori(relative.x / NATIVE_CELL_SIZE), floori(relative.y / NATIVE_CELL_SIZE))
	if cell.x < 0 or cell.y < 0 or cell.x >= visible_cells.x or cell.y >= visible_cells.y:
		return Vector2i(-1, -1)
	return camera + cell


static func coordinate_is_visible(coordinate: Vector2i, camera: Vector2i, visible_cells: Vector2i) -> bool:
	return coordinate.x >= camera.x and coordinate.y >= camera.y and coordinate.x < camera.x + visible_cells.x and coordinate.y < camera.y + visible_cells.y


static func cell_rect(coordinate: Vector2i, camera: Vector2i, draw_origin: Vector2) -> Rect2:
	return Rect2(draw_origin + Vector2(coordinate - camera) * NATIVE_CELL_SIZE, Vector2.ONE * NATIVE_CELL_SIZE)


static func footprint_rect(footprint: Array[Vector2i], camera: Vector2i, draw_origin: Vector2) -> Rect2:
	if footprint.is_empty():
		return Rect2()
	var minimum := footprint[0]
	var maximum := footprint[0]
	for coordinate: Vector2i in footprint:
		minimum = Vector2i(mini(minimum.x, coordinate.x), mini(minimum.y, coordinate.y))
		maximum = Vector2i(maxi(maximum.x, coordinate.x), maxi(maximum.y, coordinate.y))
	return Rect2(draw_origin + Vector2(minimum - camera) * NATIVE_CELL_SIZE, Vector2(maximum - minimum + Vector2i.ONE) * NATIVE_CELL_SIZE)
