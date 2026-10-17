## Chooses the detached pre-action view for one committed playback sequence.
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


