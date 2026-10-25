## Captures and schedules required death work while feedback remains event-only.
class_name CombatDeathMacroOperations
extends RefCounted


static func request_immediate(combat: CombatState, monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent]) -> bool:
	var request := CombatDeathMacroRequest.capture(combat,monster,definition,false)
	if request == null: return false
	combat.pending_operations.death_macro = request
	CombatActionEvents.append_monster_death_macro_request(request, events)
	return true


static func queue_spell(combat: CombatState, monster: MonsterState, definition: MonsterDefinition) -> bool:
	var request := CombatDeathMacroRequest.capture(combat,monster,definition,true)
	return request != null and combat.death_macros.queue(request)


static func request_next(combat: CombatState, _content: RealmzContent, events: Array[DomainEvent]) -> bool:
	var request := combat.death_macros.pending_request() if combat != null else null
	if request == null or request.macro_id == 0: return false
	combat.pending_operations.death_macro = request
	CombatActionEvents.append_monster_death_macro_request(request, events)
	return true


static func begin_pending(combat: CombatState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	if combat == null or content == null or combat.death_macros.pending_id().is_empty(): return false
	if not combat.death_macros.actor_id().is_empty(): return true
	return combat.death_macros.begin_sequence(combat.turns.active_actor_id(), false) and request_next(combat, content, events)
