## Captures a macro's native entry facts and its distinct gameplay return owner.
class_name ScenarioMacroCall
extends RefCounted

enum Kind { ROUND, DEATH }
enum ReturnKind { DIRECT, CLASSIC, SAFE, DESTRUCTION }

var kind: Kind = Kind.ROUND
var return_kind: ReturnKind = ReturnKind.DIRECT
var battle_id: String = ""
var program_id: String = ""
var caller: ScenarioBattleCaller
var combatant_id: String = ""
var classic_monster_id: int = 0
var traitor: bool = false
var has_classic_monster_id: bool = false
var has_traitor: bool = false
var reset_traitor_on_complete: bool = true
var remaining_combatant_ids: Array[String] = []
var queued_source: CombatQueuedMacroSource


static func death(request: CombatDeathMacroRequest, battle: String, returning: ReturnKind = ReturnKind.DIRECT, battle_caller: ScenarioBattleCaller = null) -> ScenarioMacroCall:
	var result := ScenarioMacroCall.new()
	result.kind = Kind.DEATH
	result.return_kind = returning
	result.battle_id = battle
	result.program_id = request.program_id()
	result.combatant_id = request.combatant_id
	result.classic_monster_id = request.classic_monster_id
	result.traitor = request.source.classic_traitor != 0
	result.has_classic_monster_id = true
	result.has_traitor = true
	result.reset_traitor_on_complete = not request.queued_by_spell
	result.queued_source = request.source.copy() if request.queued_by_spell else null
	result.caller = battle_caller.copy() if battle_caller != null else null
	return result


func entry_context() -> ScenarioExecutionContext:
	var context := ScenarioExecutionContext.calling(&"battle-macro" if kind == Kind.ROUND else &"monster-death-macro").set_battle(battle_id)
	if kind == Kind.DEATH:
		context.set_combatant(combatant_id, classic_monster_id, traitor)
		context.has_classic_monster_id = has_classic_monster_id
		context.has_traitor = has_traitor
	return context


func source_kind() -> StringName:
	return ScenarioRuntimeContinuation.SAFE_COMBAT if return_kind == ReturnKind.SAFE else ScenarioRuntimeContinuation.CLASSIC_COMBAT


func copy() -> ScenarioMacroCall:
	return from_data(to_data())


func to_data() -> Dictionary:
	return {"kind": kind, "returnKind": return_kind, "battleId": battle_id, "programId": program_id, "caller": null if caller == null else caller.to_data(), "combatantId": combatant_id, "classicMonsterId": classic_monster_id, "traitor": traitor, "hasClassicMonsterId":has_classic_monster_id, "hasTraitor":has_traitor, "resetTraitorOnComplete": reset_traitor_on_complete, "remainingCombatantIds": remaining_combatant_ids.duplicate(), "queuedSource": null if queued_source == null else queued_source.to_data()}


static func from_data(value: Variant) -> ScenarioMacroCall:
	if not ScenarioExecutionWire.fields(value, ["kind", "returnKind", "battleId", "programId", "caller", "combatantId", "classicMonsterId", "traitor", "hasClassicMonsterId", "hasTraitor", "resetTraitorOnComplete", "remainingCombatantIds", "queuedSource"]): return null
	var data: Dictionary = value
	var macro_kind := ScenarioExecutionWire.integer(data["kind"], Kind.ROUND, Kind.DEATH)
	var returning := ScenarioExecutionWire.integer(data["returnKind"], ReturnKind.DIRECT, ReturnKind.DESTRUCTION)
	var monster_id := ScenarioExecutionWire.integer(data["classicMonsterId"], 0, 32767)
	if macro_kind < 0 or returning < 0 or monster_id < 0 or not data["battleId"] is String or not data["programId"] is String or not data["combatantId"] is String or not data["traitor"] is bool or not data["hasClassicMonsterId"] is bool or not data["hasTraitor"] is bool or not data["resetTraitorOnComplete"] is bool or not data["remainingCombatantIds"] is Array: return null
	var result := ScenarioMacroCall.new()
	result.kind = macro_kind as Kind
	result.return_kind = returning as ReturnKind
	result.battle_id = data["battleId"]
	result.program_id = data["programId"]
	result.combatant_id = data["combatantId"]
	result.classic_monster_id = monster_id
	if data["queuedSource"] != null:
		result.queued_source = CombatQueuedMacroSource.from_data(data["queuedSource"])
		if result.queued_source == null: return null
	result.traitor = data["traitor"]
	result.has_classic_monster_id = data["hasClassicMonsterId"]
	result.has_traitor = data["hasTraitor"]
	result.reset_traitor_on_complete = data["resetTraitorOnComplete"]
	if data["caller"] != null:
		result.caller = ScenarioBattleCaller.from_data(data["caller"])
		if result.caller == null: return null
	var remaining: Array = data["remainingCombatantIds"]
	if remaining.size() > 100: return null
	for entry: Variant in remaining:
		if not entry is String: return null
		var identity: String = entry
		if identity.is_empty() or identity == result.combatant_id or result.remaining_combatant_ids.has(identity): return null
		result.remaining_combatant_ids.append(identity)
	return result if result.is_valid() else null


func is_valid() -> bool:
	if battle_id.is_empty() or not program_id.begins_with("xap:"): return false
	if not has_classic_monster_id and classic_monster_id != 0 or not has_traitor and traitor: return false
	if (queued_source != null) != (kind == Kind.DEATH and not reset_traitor_on_complete): return false
	if queued_source != null and queued_source.available and traitor != (queued_source.classic_traitor != 0): return false
	if return_kind in [ReturnKind.CLASSIC, ReturnKind.SAFE]:
		if caller == null or caller.kind != (ScenarioBattleCaller.CLASSIC if return_kind == ReturnKind.CLASSIC else ScenarioBattleCaller.SAFE): return false
	elif caller != null: return false
	if return_kind != ReturnKind.DESTRUCTION and not remaining_combatant_ids.is_empty(): return false
	if kind == Kind.ROUND:
		return return_kind != ReturnKind.DESTRUCTION and combatant_id.is_empty() and classic_monster_id == 0 and not traitor and not has_classic_monster_id and not has_traitor and reset_traitor_on_complete
	return not combatant_id.is_empty()
