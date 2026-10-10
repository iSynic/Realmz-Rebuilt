## Selects Castle's exact skull resource for a defeated combatant's native footprint.

class_name CombatDefeatArt
extends RefCounted


static func resource_id_for_combatant(view: GameView, combatant_id: String) -> int:
	if view == null or view.combat_view == null or view.combat_view.battlefield == null:
		return 2015
	return resource_id_for_footprint(view.combat_view.battlefield.monster_footprint(combatant_id))


static func resource_id_for_footprint(footprint: Array[Vector2i]) -> int:
	if footprint.size() == 4:
		return 2018
	if footprint.size() == 2:
		return 2016 if footprint[0].x == footprint[1].x else 2017
	return 2015


static func draw(canvas: CanvasItem, media: ClassicMediaCatalog, textures: BattlefieldTextureCache, resource_id: int, coordinate: Vector2i, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2) -> Dictionary:
	var asset := media.asset_by_resource("cicn", resource_id) if media != null else null
	var texture := textures.actor_texture(asset)
	var diagnostic := media.resolution_diagnostic("cicn", resource_id, "classic-combat-defeat", "decoded" if texture != null else "decode-failed") if media != null else {"resourceType": "cicn", "resourceId": resource_id, "status": "catalog-unavailable"}
	if texture == null:
		return diagnostic
	var marker_size := texture.get_size()
	var anchor_rect := BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin)
	var marker_rect := Rect2(anchor_rect.position - marker_size + Vector2.ONE * BattlefieldPresentationGeometry.NATIVE_CELL_SIZE, marker_size)
	var visible_rect := marker_rect.intersection(Rect2(draw_origin, Vector2(visible_cells) * BattlefieldPresentationGeometry.NATIVE_CELL_SIZE))
	if visible_rect.has_area():
		canvas.draw_texture_rect_region(texture, visible_rect, ClassicCombatBackdrop.clipped_source(marker_rect, Rect2(Vector2.ZERO, marker_size), visible_rect))
	return diagnostic
