class_name SessionDebugCommand
extends RefCounted

enum Kind { WARP, NOCLIP_STEP, RESTORE_PARTY, START_ENCOUNTER, START_BATTLE, WIN_BATTLE }

var kind: Kind
var map_id: String = ""
var coordinate: Vector2i = Vector2i.ZERO
var classic_id: int = -1
var encounter_kind: StringName = &"simple"


func _init(command_kind: Kind) -> void:
	kind = command_kind


static func warp(target_map_id: String, target: Vector2i) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.WARP)
	command.map_id = target_map_id
	command.coordinate = target
	return command


static func noclip_step(direction: Vector2i) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.NOCLIP_STEP)
	command.coordinate = direction
	return command


static func restore_party() -> SessionDebugCommand:
	return SessionDebugCommand.new(Kind.RESTORE_PARTY)


static func start_encounter(type: StringName, encounter_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_ENCOUNTER)
	command.encounter_kind = type
	command.classic_id = encounter_id
	return command


static func start_battle(battle_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_BATTLE)
	command.classic_id = battle_id
	return command


static func win_battle() -> SessionDebugCommand:
	return SessionDebugCommand.new(Kind.WIN_BATTLE)
