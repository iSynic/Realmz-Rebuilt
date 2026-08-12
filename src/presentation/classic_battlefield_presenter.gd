class_name ClassicBattlefieldPresenter
extends Control

signal tactical_action_requested(payload: Dictionary)

const NATIVE_CELL_SIZE: float = 32.0
const HEADER_HEIGHT: float = 38.0
const MAX_VISIBLE_COLUMNS: int = 16
const MAX_VISIBLE_ROWS: int = 14

var _view: GameView
var _media: PackageMediaCatalog
var _atlas_asset: PackageMediaAsset
var _atlas_texture: Texture2D
var _upper_atlas_id: String = ""
var _upper_atlas_asset: PackageMediaAsset
var _upper_atlas_texture: Texture2D
var _actor_textures: Dictionary = {}
var _movement_costs_visible: bool = false
var _hovered_coordinate := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func present(game_view: GameView) -> void:
	_view = game_view
	if _view == null or _view.combat_view == null:
		_movement_costs_visible = false
		_hovered_coordinate = Vector2i(-1, -1)
	var requested_upper_atlas_id := ""
	if _view != null and _view.combat_view != null and _view.combat_view.battlefield != null:
		requested_upper_atlas_id = _view.combat_view.battlefield.upper_tileset_id
	if requested_upper_atlas_id != _upper_atlas_id:
		_upper_atlas_id = requested_upper_atlas_id
		_upper_atlas_asset = _media.tileset_by_id(_upper_atlas_id) if _media != null and not _upper_atlas_id.is_empty() else null
		_upper_atlas_texture = _load_image_texture(_upper_atlas_asset)
	queue_redraw()


func set_media_catalog(media: PackageMediaCatalog) -> void:
	_media = media
	_atlas_asset = null
	_atlas_texture = null
	_upper_atlas_id = ""
	_upper_atlas_asset = null
	_upper_atlas_texture = null
	_actor_textures.clear()
	if _media != null:
		_atlas_asset = _media.battle_tileset()
		_atlas_texture = _load_image_texture(_atlas_asset)
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
	var combat := _view.combat_view
	var battlefield := combat.battlefield
	var active_position := actor_position(combat, _view.party_members, combat.active_actor_id)
	if active_position.x < 0:
		active_position = battlefield.party_anchor
	var visible_cells := viewport_cells_for(size)
	var camera := camera_top_left(active_position, visible_cells)
	var draw_origin := battlefield_draw_origin(size, visible_cells)
	_draw_header(combat)
	for y: int in visible_cells.y:
		for x: int in visible_cells.x:
			var coordinate := camera + Vector2i(x, y)
			var rect := Rect2(draw_origin + Vector2(x, y) * NATIVE_CELL_SIZE, Vector2.ONE * NATIVE_CELL_SIZE)
			_draw_terrain_cell(battlefield.terrain_at(coordinate), rect)
	_draw_movement_options(combat, camera, visible_cells, draw_origin)
	_draw_characters(combat, camera, visible_cells, draw_origin)
	_draw_monsters(combat, camera, visible_cells, draw_origin)
	if not has_battle_artwork():
		draw_string(ThemeDB.fallback_font, Vector2(draw_origin.x + 8.0, draw_origin.y + 20.0), "Battle artwork unavailable", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1.0, 0.78, 0.42))


func _draw_header(combat: CombatView) -> void:
	var current_actor_name := actor_name(combat, _view.party_members, combat.active_actor_id)
	var title := "Battle %s • Round %d • %s" % [combat.battle_id, combat.round_number, current_actor_name]
	var facts := "%d attack%s • %d movement • %s" % [combat.attack_units_remaining, "" if combat.attack_units_remaining == 1 else "s", combat.movement_remaining, String(combat.weapon_mode).capitalize()]
	draw_string(ThemeDB.fallback_font, Vector2(8.0, 17.0), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 250.0, 120.0), 16, Color(0.86, 0.75, 0.42))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 242.0, 17.0), facts, HORIZONTAL_ALIGNMENT_RIGHT, 234.0, 12, Color(0.73, 0.76, 0.80))


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
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(2.0, 20.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0, 11, Color(1.0, 0.94, 0.68))
		else:
			draw_rect(rect, Color(0.10, 0.08, 0.08, 0.52), true)
			draw_rect(rect, Color(0.70, 0.30, 0.26, 0.78), false, 1.0)
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(2.0, 20.0), "—", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 4.0, 12, Color(0.90, 0.62, 0.56))


func set_movement_costs_visible(visible_costs: bool) -> void:
	if _movement_costs_visible == visible_costs:
		return
	_movement_costs_visible = visible_costs
	queue_redraw()


func movement_costs_visible() -> bool:
	return _movement_costs_visible


func submit_movement_direction(direction: Vector2i) -> bool:
	var option := _movement_option_for_direction(direction)
	return _submit_movement_option(option)


func _gui_input(event: InputEvent) -> void:
	if _view == null or _view.combat_view == null or _view.combat_view.battlefield == null:
		return
	if event is InputEventMouseMotion:
		var coordinate := _coordinate_at_local_position((event as InputEventMouseMotion).position)
		var next_hover := coordinate if _movement_option_for_destination(coordinate) != null else Vector2i(-1, -1)
		if next_hover != _hovered_coordinate:
			_hovered_coordinate = next_hover
			queue_redraw()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
		var coordinate := _coordinate_at_local_position((event as InputEventMouseButton).position)
		if _submit_movement_option(_movement_option_for_destination(coordinate)):
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered_coordinate != Vector2i(-1, -1):
		_hovered_coordinate = Vector2i(-1, -1)
		queue_redraw()


func _coordinate_at_local_position(local_position: Vector2) -> Vector2i:
	var combat := _view.combat_view
	var battlefield := combat.battlefield
	var active_position := actor_position(combat, _view.party_members, combat.active_actor_id)
	if active_position.x < 0:
		active_position = battlefield.party_anchor
	var visible_cells := viewport_cells_for(size)
	var camera := camera_top_left(active_position, visible_cells)
	var draw_origin := battlefield_draw_origin(size, visible_cells)
	var relative := local_position - draw_origin
	if relative.x < 0.0 or relative.y < 0.0:
		return Vector2i(-1, -1)
	var cell := Vector2i(floori(relative.x / NATIVE_CELL_SIZE), floori(relative.y / NATIVE_CELL_SIZE))
	if cell.x < 0 or cell.y < 0 or cell.x >= visible_cells.x or cell.y >= visible_cells.y:
		return Vector2i(-1, -1)
	return camera + cell


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


func _submit_movement_option(option: CombatMoveOptionView) -> bool:
	if option == null or not option.enabled or _view == null or _view.combat_view == null:
		return false
	var payload := {
		"actorId": _view.combat_view.active_actor_id,
		"action": "retreat_edge" if option.retreats_from_battle else "move",
		"targetId": "",
		"destination": [option.destination.x, option.destination.y],
	}
	if option.retreats_from_battle:
		payload["forced"] = option.forced_retreat
	tactical_action_requested.emit(payload)
	return true


func _draw_characters(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	var target_ids: Dictionary = {}
	for target: CharacterView in combat.character_targets:
		target_ids[target.id] = true
	for character: CharacterView in _view.party_members:
		var coordinate := combat.battlefield.character_position(character.id)
		if not coordinate_is_visible(coordinate, camera, visible_cells):
			continue
		var rect := cell_rect(coordinate, camera, draw_origin)
		var asset := _media.asset_by_id(character.combat_icon_id) if _media != null else null
		_draw_actor(rect, _texture_for(asset), character.name, character.id == combat.active_actor_id, target_ids.has(character.id), character.traitor)


func _draw_monsters(combat: CombatView, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> void:
	var target_ids: Dictionary = {}
	for target: MonsterView in combat.targets:
		target_ids[target.id] = true
	for monster: MonsterView in combat.monsters:
		var footprint := combat.battlefield.monster_footprint(monster.id)
		var visible_footprint: Array[Vector2i] = []
		for coordinate: Vector2i in footprint:
			if coordinate_is_visible(coordinate, camera, visible_cells):
				visible_footprint.append(coordinate)
		if visible_footprint.is_empty():
			continue
		var rect := footprint_rect(visible_footprint, camera, draw_origin)
		var asset := _media.asset_by_resource(monster.icon_resource_type, monster.icon_id) if _media != null else null
		_draw_actor(rect, _texture_for(asset), monster.name, monster.id == combat.active_actor_id, target_ids.has(monster.id), monster.traitor)


func _draw_actor(rect: Rect2, texture: Texture2D, label: String, active: bool, target: bool, hostile: bool) -> void:
	if texture != null:
		draw_texture_rect(texture, rect, false)
	else:
		draw_rect(rect.grow(-3.0), Color(0.62, 0.20, 0.18) if hostile else Color(0.18, 0.42, 0.64), true)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(5.0, 20.0), label.left(2).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color.WHITE)
	if target:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.35, 0.26), false, 3.0)
	if active:
		draw_rect(rect.grow(2.0), Color(0.98, 0.82, 0.25), false, 3.0)


func _texture_for(asset: PackageMediaAsset) -> Texture2D:
	if asset == null:
		return null
	if _actor_textures.has(asset.id):
		return _actor_textures[asset.id] as Texture2D
	var texture := _load_image_texture(asset)
	_actor_textures[asset.id] = texture
	return texture


func _load_image_texture(asset: PackageMediaAsset) -> Texture2D:
	if asset == null or _media == null:
		return null
	var bytes := _media.read_bytes(asset)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match asset.mime_type:
		"image/png":
			error = image.load_png_from_buffer(bytes)
		"image/jpeg":
			error = image.load_jpg_from_buffer(bytes)
		"image/webp":
			error = image.load_webp_from_buffer(bytes)
	if error != OK:
		return null
	if asset.width > 0 and asset.height > 0 and (image.get_width() != asset.width or image.get_height() != asset.height):
		return null
	return ImageTexture.create_from_image(image)


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


static func viewport_cells_for(control_size: Vector2) -> Vector2i:
	return Vector2i(
		mini(MAX_VISIBLE_COLUMNS, maxi(1, floori(control_size.x / NATIVE_CELL_SIZE))),
		mini(MAX_VISIBLE_ROWS, maxi(1, floori((control_size.y - HEADER_HEIGHT) / NATIVE_CELL_SIZE)))
	)


static func camera_top_left(active_position: Vector2i, visible_cells: Vector2i) -> Vector2i:
	var maximum := Vector2i(BattlefieldState.SIZE, BattlefieldState.SIZE) - visible_cells
	return Vector2i(
		clampi(active_position.x - floori(float(visible_cells.x) / 2.0), 0, maximum.x),
		clampi(active_position.y - floori(float(visible_cells.y) / 2.0), 0, maximum.y)
	)


static func battlefield_draw_origin(control_size: Vector2, visible_cells: Vector2i) -> Vector2:
	var pixel_size := Vector2(visible_cells) * NATIVE_CELL_SIZE
	return Vector2(
		floorf((control_size.x - pixel_size.x) * 0.5),
		HEADER_HEIGHT + floorf(maxf(control_size.y - HEADER_HEIGHT - pixel_size.y, 0.0) * 0.5)
	)


static func coordinate_is_visible(coordinate: Vector2i, camera: Vector2i, visible_cells: Vector2i) -> bool:
	return coordinate.x >= camera.x and coordinate.y >= camera.y and coordinate.x < camera.x + visible_cells.x and coordinate.y < camera.y + visible_cells.y


static func cell_rect(coordinate: Vector2i, camera: Vector2i, draw_origin: Vector2) -> Rect2:
	return Rect2(draw_origin + Vector2(coordinate - camera) * NATIVE_CELL_SIZE, Vector2.ONE * NATIVE_CELL_SIZE)


static func footprint_rect(footprint: Array[Vector2i], camera: Vector2i, draw_origin: Vector2) -> Rect2:
	var minimum := footprint[0]
	var maximum := footprint[0]
	for coordinate: Vector2i in footprint:
		minimum = Vector2i(mini(minimum.x, coordinate.x), mini(minimum.y, coordinate.y))
		maximum = Vector2i(maxi(maximum.x, coordinate.x), maxi(maximum.y, coordinate.y))
	return Rect2(draw_origin + Vector2(minimum - camera) * NATIVE_CELL_SIZE, Vector2(maximum - minimum + Vector2i.ONE) * NATIVE_CELL_SIZE)
