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
