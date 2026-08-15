class_name ClassicOpcodeCatalog
extends RefCounted

const AOGM_ACTIVE_OPCODES: Array[int] = [
	-23, -14,
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
	21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 35, 36, 37, 38, 39,
	40, 42, 43, 45, 46, 47, 48, 49, 51, 52, 54, 56, 88, 89, 99, 104, 107,
	121, 122, 124,
]

const OWNER_BY_OPCODE: Dictionary = {
	-23: &"world-time", -14: &"character",
	1: &"presentation", 2: &"combat-rewards", 3: &"encounters", 4: &"encounters",
	5: &"encounters", 6: &"inventory-economy", 7: &"control-flow", 8: &"control-flow",
	9: &"presentation", 10: &"combat-rewards", 11: &"combat-rewards", 12: &"world-time",
	13: &"world-time", 14: &"character", 15: &"character", 16: &"character",
	17: &"character", 18: &"character", 19: &"presentation", 20: &"world-time",
	21: &"inventory-economy", 22: &"inventory-economy", 23: &"world-time", 24: &"control-flow",
	25: &"control-flow", 26: &"presentation", 27: &"presentation", 28: &"presentation",
	29: &"world-time", 30: &"character", 31: &"character", 32: &"inventory-economy",
	33: &"inventory-economy", 34: &"encounters", 35: &"encounters", 36: &"inventory-economy",
	37: &"world-time", 38: &"inventory-economy", 39: &"vm-control-flow", 40: &"character",
	42: &"control-flow", 43: &"character", 45: &"world-time", 46: &"control-flow",
	47: &"world-time", 48: &"combat-rewards", 49: &"inventory-economy", 50: &"character",
	51: &"inventory-economy", 52: &"character", 54: &"encounters", 56: &"combat-rewards",
	60: &"inventory-economy", 61: &"world-time", 62: &"presentation", 63: &"world-time",
	64: &"control-flow", 65: &"inventory-economy", 66: &"world-time", 69: &"character",
	73: &"inventory-economy", 76: &"world-time", 77: &"control-flow", 82: &"character",
	83: &"character", 86: &"control-flow", 87: &"character", 88: &"character",
	89: &"character", 90: &"character", 91: &"inventory-economy", 98: &"control-flow",
	99: &"control-flow", 101: &"world-time", 102: &"character", 103: &"world-time",
	104: &"world-time", 105: &"character", 106: &"world-time", 107: &"combat-rewards",
	108: &"character", 111: &"vm-control-flow", 112: &"vm-control-flow", 119: &"combat-rewards",
	120: &"combat-rewards", 121: &"combat-rewards", 122: &"combat-rewards", 123: &"combat-rewards",
	124: &"combat-rewards", 126: &"combat-rewards", 127: &"combat-rewards",
}

const VM_CONTROL_FLOW_OPCODES: Array[int] = [39, 111, 112]

const EXECUTABLE_OPCODES: Array[int] = [
	-23, -14,
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
	20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 35, 36, 37, 38, 39,
	34, 40, 42, 43, 45, 46, 47, 48, 49, 51, 52, 54, 56, 88, 89, 98, 99, 104, 107,
	50, 60, 61, 62, 63, 64, 65, 66, 69, 73, 76, 77, 82, 83, 86, 87, 90, 91, 101, 102, 103, 105, 106, 108, 111, 112, 119, 120, 121, 122, 123, 124, 126, 127,
]


static func normalize(raw_opcode: int) -> int:
	return -raw_opcode if raw_opcode < 0 and raw_opcode not in [-14, -23] else raw_opcode


static func owner(opcode: int) -> StringName:
	return OWNER_BY_OPCODE.get(opcode, &"") as StringName


static func is_owned(opcode: int) -> bool:
	return not owner(opcode).is_empty()


static func is_executable(opcode: int) -> bool:
	return EXECUTABLE_OPCODES.has(opcode)


static func runtime_handler_opcodes() -> Array[int]:
	var result: Array[int] = []
	for opcode: int in EXECUTABLE_OPCODES:
		if not VM_CONTROL_FLOW_OPCODES.has(opcode):
			result.append(opcode)
	result.sort()
	return result
