## Captures one death macro when its source effect commits; legacy IDs stay unavailable.
class_name CombatDeathMacroRequest
extends RefCounted

var combatant_id: String = ""
var definition_id: String = ""
var classic_monster_id: int = 0
var macro_id: int = 0
var queued_by_spell: bool = false
var source := CombatQueuedMacroSource.new()


static func capture(combat: CombatState, monster: MonsterState, definition: MonsterDefinition, queued: bool) -> CombatDeathMacroRequest:
	if combat == null or monster == null or definition == null or not definition.has_death_macro(): return null
	var result := CombatDeathMacroRequest.new()
	result.combatant_id = monster.id
	result.definition_id = definition.id
	result.classic_monster_id = definition.classic_id
	result.macro_id = definition.death_macro
	result.queued_by_spell = queued
	result.source = CombatQueuedMacroSource.capture(combat,monster,definition)
	return result if result.source.available else null


static func legacy(combatant: String) -> CombatDeathMacroRequest:
	var result := CombatDeathMacroRequest.new()
	result.combatant_id = combatant
	result.queued_by_spell = true
	return result


func program_id() -> String:
	return "xap:%d" % macro_id


func copy() -> CombatDeathMacroRequest:
	return from_data(to_data())


func to_data() -> Dictionary:
	return {"combatantId":combatant_id,"definitionId":definition_id,"classicMonsterId":classic_monster_id,"macroId":macro_id,"queuedBySpell":queued_by_spell,"source":source.to_data()}


static func from_data(value: Variant) -> CombatDeathMacroRequest:
	if not value is Dictionary: return null
	var data: Dictionary = value
	if data.size() != 6 or not data.has_all(["combatantId","definitionId","classicMonsterId","macroId","queuedBySpell","source"]): return null
	if not data["combatantId"] is String or not data["definitionId"] is String or not data["queuedBySpell"] is bool: return null
	var result := CombatDeathMacroRequest.new()
	result.combatant_id = data["combatantId"]
	result.definition_id = data["definitionId"]
	result.queued_by_spell = data["queuedBySpell"]
	result.classic_monster_id = CombatQueuedMacroSource.integer(data["classicMonsterId"],0,32767)
	result.macro_id = CombatQueuedMacroSource.integer(data["macroId"],-32768,32767)
	result.source = CombatQueuedMacroSource.from_data(data["source"])
	if result.combatant_id.is_empty() or result.combatant_id.length() > 256 or result.definition_id.length() > 256 or result.source == null or result.classic_monster_id < 0 or result.macro_id < -32768: return null
	if result.macro_id == 0:
		return result if result.queued_by_spell and result.definition_id.is_empty() and result.classic_monster_id == 0 and not result.source.available else null
	return result if result.source.available and not result.definition_id.is_empty() else null
