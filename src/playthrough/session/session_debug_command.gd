## Defines the typed session debug command contract used by playthrough transactions.

class_name SessionDebugCommand
extends RefCounted

enum Kind { WARP, NOCLIP_STEP, RESTORE_PARTY, START_ACTION_POINT, START_EXTRA_ACTION_POINT_PROGRAM, START_ENCOUNTER, START_SCROLLING_TEXT, START_BATTLE, START_TREASURE, START_SHOP, WIN_BATTLE }

var kind: Kind
var map_id: String = ""
var coordinate: Vector2i = Vector2i.ZERO
var classic_id: int = -1
var encounter_kind: StringName = &"simple"
var target_id: String = ""


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


static func start_action_point(trigger_id: String) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_ACTION_POINT)
	command.target_id = trigger_id
	return command


static func start_extra_action_point_program(native_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_EXTRA_ACTION_POINT_PROGRAM)
	command.classic_id = native_id
	return command


static func start_encounter(type: StringName, encounter_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_ENCOUNTER)
	command.encounter_kind = type
	command.classic_id = encounter_id
	return command


static func start_scrolling_text(resource_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_SCROLLING_TEXT)
	command.classic_id = resource_id
	return command


static func start_battle(battle_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_BATTLE)
	command.classic_id = battle_id
	return command


static func start_treasure(treasure_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_TREASURE)
	command.classic_id = treasure_id
	return command


static func start_shop(shop_id: int) -> SessionDebugCommand:
	var command := SessionDebugCommand.new(Kind.START_SHOP)
	command.classic_id = shop_id
	return command


static func win_battle() -> SessionDebugCommand:
	return SessionDebugCommand.new(Kind.WIN_BATTLE)
