## Retains killbody's captured subject facts without consulting later mutations.
class_name CombatQueuedMacroSource
extends RefCounted

var available: bool = false
var monster_index: int = 0
var native_name_id: int = 0
var classic_traitor: int = 0
var has_position: bool = false
var position: Vector2i = Vector2i.ZERO


static func capture(combat: CombatState, monster: MonsterState, definition: MonsterDefinition) -> CombatQueuedMacroSource:
	var result := CombatQueuedMacroSource.new()
	var index := combat.roster.monsters().find(monster)
	if index < 0: return result
	result.available = true
	result.monster_index = index
	result.native_name_id = definition.classic_name_id
	result.classic_traitor = monster.classic_traitor
	result.has_position = combat.battlefield != null and combat.battlefield.actors.has_actor(monster.id)
	if result.has_position: result.position = combat.battlefield.actors.actor_position(monster.id)
	return result


func copy() -> CombatQueuedMacroSource:
	return from_data(to_data())


func to_data() -> Dictionary:
	return {"available":available,"monsterIndex":monster_index,"nativeNameId":native_name_id,"classicTraitor":classic_traitor,"hasPosition":has_position,"x":position.x,"y":position.y}


static func from_data(value: Variant) -> CombatQueuedMacroSource:
	if not value is Dictionary: return null
	var data: Dictionary = value
	if data.size() != 7 or not data.has_all(["available","monsterIndex","nativeNameId","classicTraitor","hasPosition","x","y"]): return null
	if not data["available"] is bool or not data["hasPosition"] is bool: return null
	var result := CombatQueuedMacroSource.new()
	result.available = data["available"]
	result.has_position = data["hasPosition"]
	result.monster_index = integer(data["monsterIndex"],0,99)
	result.native_name_id = integer(data["nativeNameId"],0,255)
	result.classic_traitor = integer(data["classicTraitor"],-128,127)
	var x := integer(data["x"],0,BattlefieldGrid.SIZE-1)
	var y := integer(data["y"],0,BattlefieldGrid.SIZE-1)
	if result.monster_index < 0 or result.native_name_id < 0 or result.classic_traitor < -128 or x < 0 or y < 0: return null
	result.position = Vector2i(x,y)
	if not result.has_position and result.position != Vector2i.ZERO: return null
	if not result.available and (result.monster_index != 0 or result.native_name_id != 0 or result.classic_traitor != 0 or result.has_position): return null
	return result


static func integer(value: Variant, minimum: int, maximum: int) -> int:
	if value is int:
		var number: int = value
		return number if number >= minimum and number <= maximum else minimum-1
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum: return int(number)
	return minimum-1
