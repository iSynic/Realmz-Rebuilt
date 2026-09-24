## Observes complete automated rounds without becoming saved gameplay state.
class_name AutoProgressMonitor
extends RefCounted

var _battle_id := ""
var _round := -1
var _snapshot: Array = []
var _activity := false
var _empty_rounds := 0


func reset() -> void:
	_battle_id = ""
	_round = -1
	_snapshot.clear()
	_activity = false
	_empty_rounds = 0


func before_activation(view: GameView) -> bool:
	var combat := view.combat_view
	if combat == null or combat.outcome != &"active" or view.pending_interaction != null and view.pending_interaction.kind != InteractionRequest.COMBAT:
		reset()
		return false
	var party_ids: Array[String] = []
	for member: CharacterView in view.party_members:
		if member.current_health > 0 and combat.friendly_actor_ids.has(member.id) and combat.battlefield.character_position(member.id).x >= 0:
			if not combat.auto_character_ids.has(member.id):
				reset()
				return false
			party_ids.append(member.id)
	var first := ""
	for actor_id: String in combat.turn_order:
		if party_ids.has(actor_id):
			first = actor_id
			break
	if _battle_id != combat.battle_id:
		reset()
		_battle_id = combat.battle_id
	if first.is_empty() or combat.active_actor_id != first or combat.round_number == _round:
		return false
	var snapshot := _facts(view)
	if _round >= 0 and combat.round_number == _round + 1:
		_empty_rounds = 0 if _activity or snapshot != _snapshot else _empty_rounds + 1
	else:
		_empty_rounds = 0
	_round = combat.round_number
	_snapshot = snapshot
	_activity = false
	return _empty_rounds >= 2


func observe(events: Array[DomainEvent]) -> void:
	for event: DomainEvent in events:
		if event.kind in [&"combat_attack_resolved", &"combat_projectile_resolved", &"combat_spell_resolved", &"combat_scroll_resolved", &"combat_item_resolved", &"combatant_bandaged", &"combat_persistent_field_expired", &"combatant_bleeding_progressed"]:
			_activity = true


func _facts(view: GameView) -> Array:
	var result: Array = []
	var combat := view.combat_view
	for member: CharacterView in view.party_members:
		result.append([member.id, member.current_health, member.condition_values.duplicate(), combat.battlefield.character_position(member.id)])
	for monster: MonsterView in combat.monsters:
		result.append([monster.id, monster.current_health, monster.condition_values.duplicate(), combat.battlefield.monster_position(monster.id)])
	for field: PersistentCombatFieldView in combat.persistent_fields:
		result.append([field.slot, field.remaining_duration])
	return result
