## Builds Castle's Reveal Friends and combat hash-mark relationship lines for battle presentation.

class_name BattlefieldRelationshipLines
extends RefCounted

const HOSTILE := Color(0.95, 0.22, 0.18, 0.86)
const FRIENDLY := Color(0.18, 0.90, 0.38, 0.86)
const HELPLESS := Color(0.20, 0.42, 1.0, 0.90)
## centerfield.c restores everything but a 10-pixel look-window border after drawing hash-mark lines.
const HASH_MARK_BAND := 10.0


## Line segments as start/end point pairs, with one color per segment, ready for draw_multiline_colors.
class Segments:
	var points := PackedVector2Array()
	var colors := PackedColorArray()

	func add(start: Vector2, end: Vector2, color: Color) -> void:
		points.append(start)
		points.append(end)
		colors.append(color)


## showrange.c draws from the active character to every living combatant and lets the look port clip
## lines whose far end is off-screen, so each segment ends at the stage edge in that combatant's direction.
static func reveal_segments(combat: CombatView, party_members: Array[CharacterView], camera: Vector2i, draw_origin: Vector2, stage: Rect2) -> Segments:
	var lines := _relationships(combat, party_members, camera, draw_origin)
	var result := Segments.new()
	for index: int in lines.colors.size():
		var start := lines.points[index * 2]
		var end := lines.points[index * 2 + 1]
		var span := _clip_span(start, end, stage)
		if not span.is_empty():
			result.add(start.lerp(end, span[0]), start.lerp(end, span[1]), lines.colors[index])
	return result


## Usehashmarks keeps only the parts of those clipped lines inside the stage's outer band.
static func hash_mark_segments(combat: CombatView, party_members: Array[CharacterView], camera: Vector2i, draw_origin: Vector2, stage: Rect2) -> Segments:
	var lines := _relationships(combat, party_members, camera, draw_origin)
	var result := Segments.new()
	var inner := stage.grow(-HASH_MARK_BAND)
	for index: int in lines.colors.size():
		var start := lines.points[index * 2]
		var end := lines.points[index * 2 + 1]
		var color := lines.colors[index]
		var span := _clip_span(start, end, stage)
		if span.is_empty():
			continue
		var hidden := _clip_span(start, end, inner) if inner.has_area() else PackedFloat32Array()
		if hidden.is_empty() or hidden[1] <= span[0] or hidden[0] >= span[1]:
			result.add(start.lerp(end, span[0]), start.lerp(end, span[1]), color)
			continue
		if hidden[0] > span[0]:
			result.add(start.lerp(end, span[0]), start.lerp(end, hidden[0]), color)
		if hidden[1] < span[1]:
			result.add(start.lerp(end, hidden[1]), start.lerp(end, span[1]), color)
	return result


static func _relationships(combat: CombatView, party_members: Array[CharacterView], camera: Vector2i, draw_origin: Vector2) -> Segments:
	var result := Segments.new()
	var origin := BattlefieldPresentationGeometry.actor_position(combat, party_members, combat.active_actor_id)
	if origin.x < 0:
		return result
	var start := BattlefieldPresentationGeometry.cell_rect(origin, camera, draw_origin).get_center()
	for character: CharacterView in party_members:
		var coordinate := combat.battlefield.character_position(character.id)
		if character.id == combat.active_actor_id or coordinate.x < 0:
			continue
		var color := HELPLESS if character.condition_values[ConditionRules.HELPLESS] != 0 else FRIENDLY if combat.friendly_actor_ids.has(character.id) else HOSTILE
		result.add(start, BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin).get_center(), color)
	for monster: MonsterView in combat.monsters:
		var footprint := combat.battlefield.monster_footprint(monster.id)
		if monster.id == combat.active_actor_id or monster.current_health <= 0 or footprint.is_empty():
			continue
		var color := HELPLESS if monster.helpless else FRIENDLY if combat.friendly_actor_ids.has(monster.id) else HOSTILE
		result.add(start, BattlefieldPresentationGeometry.footprint_rect(footprint, camera, draw_origin).get_center(), color)
	return result


## Liang-Barsky clip: the [entry, exit] parameters of the segment inside the rectangle, or empty.
static func _clip_span(start: Vector2, end: Vector2, rect: Rect2) -> PackedFloat32Array:
	var delta := end - start
	var entry := 0.0
	var exit := 1.0
	var directions := PackedFloat32Array([-delta.x, delta.x, -delta.y, delta.y])
	var distances := PackedFloat32Array([start.x - rect.position.x, rect.end.x - start.x, start.y - rect.position.y, rect.end.y - start.y])
	for edge: int in 4:
		if is_zero_approx(directions[edge]):
			if distances[edge] < 0.0:
				return PackedFloat32Array()
			continue
		var t := distances[edge] / directions[edge]
		if directions[edge] < 0.0:
			entry = maxf(entry, t)
		else:
			exit = minf(exit, t)
		if entry > exit:
			return PackedFloat32Array()
	return PackedFloat32Array([entry, exit])
