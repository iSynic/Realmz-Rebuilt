## Projects detached playback views, coordinates and recipient camera focus.
class_name CombatPlaybackViews
extends RefCounted


static func base_for(previous: GameView, final: GameView, events: Array[DomainEvent]) -> GameView:
	for event: DomainEvent in events:
		if event is BattleStartedEvent:
			var shell := final if final != null else previous
			if shell == null:
				return null
			var opening := GameView.new(shell.revision, true, null, shell.party_map_id, shell.party_coordinate, shell.realmz_day, shell.realmz_hour, shell.realmz_minute, shell.map_view, event.opening_party, shell.party_fatigue, shell.pooled_gold, event.opening_combat)
			opening.campaign_id = shell.campaign_id
			opening.rules_version = shell.rules_version
			opening.party_summary = shell.party_summary
			opening.campaign_summary = shell.campaign_summary
			return opening
	if previous != null and previous.combat_view != null and previous.combat_view.battlefield != null:
		return previous
	if final != null and final.combat_view != null and final.combat_view.battlefield != null:
		return final
	return null


static func positions_for(view: GameView) -> Dictionary:
	var result: Dictionary = {}
	if view == null or view.combat_view == null or view.combat_view.battlefield == null:
		return result
	for character: CharacterView in view.party_members:
		var coordinate := view.combat_view.battlefield.character_position(character.id)
		if coordinate.x >= 0:
			result[character.id] = coordinate
	for monster: MonsterView in view.combat_view.monsters:
		var coordinate := view.combat_view.battlefield.monster_position(monster.id)
		if coordinate.x >= 0:
			result[monster.id] = coordinate
	return result


static func assign_camera_focus_ids(frames: Array[CombatPlaybackFrame]) -> void:
	var latest_focus_id := ""
	for frame: CombatPlaybackFrame in frames:
		var frame_focus_id := frame.actor_id if not frame.actor_id.is_empty() else frame.target_id
		if frame.kind in [&"result", &"spell_effect", &"defeat"] and not frame.target_id.is_empty():
			frame_focus_id = frame.target_id
		if not frame_focus_id.is_empty():
			latest_focus_id = frame_focus_id
		frame.camera_focus_id = latest_focus_id
	var next_focus_id := ""
	for index: int in range(frames.size() - 1, -1, -1):
		var frame := frames[index]
		if not frame.camera_focus_id.is_empty():
			next_focus_id = frame.camera_focus_id
		elif not next_focus_id.is_empty():
			frame.camera_focus_id = next_focus_id


static func payload_coordinate(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array:
		var coordinate: Array = value
		if coordinate.size() == 2:
			var x: int = coordinate[0]
			var y: int = coordinate[1]
			return Vector2i(x, y)
	return Vector2i(-1, -1)


static func combatant_position(view: GameView, combatant_id: String) -> Vector2i:
	if view == null or view.combat_view == null:
		return Vector2i(-1, -1)
	return BattlefieldPresentationGeometry.actor_position(view.combat_view, view.party_members, combatant_id)
