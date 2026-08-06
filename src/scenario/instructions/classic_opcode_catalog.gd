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
	-23: &"world",
	-14: &"characters",
	0: &"control-flow",
	1: &"presentation", 2: &"combat", 3: &"encounters", 4: &"encounters",
	5: &"encounters", 6: &"inventory", 7: &"rules-state", 8: &"rules-state",
	9: &"presentation", 10: &"inventory", 11: &"characters", 12: &"world",
	13: &"world", 14: &"characters", 15: &"characters", 16: &"characters",
	17: &"characters", 18: &"characters", 19: &"presentation", 20: &"world",
	21: &"inventory", 22: &"inventory", 23: &"world", 24: &"control-flow",
	25: &"control-flow", 26: &"presentation", 27: &"presentation", 28: &"world",
	29: &"world", 30: &"characters", 31: &"characters", 32: &"inventory",
	33: &"inventory", 34: &"encounters", 35: &"encounters", 36: &"inventory",
	37: &"world", 38: &"inventory", 39: &"control-flow", 40: &"characters",
	41: &"encounters", 42: &"control-flow", 43: &"characters", 44: &"encounters",
	45: &"world", 46: &"control-flow", 47: &"rules-state", 48: &"combat",
	49: &"inventory", 50: &"characters", 51: &"inventory", 52: &"characters",
	53: &"characters", 54: &"world", 55: &"characters", 56: &"combat",
	57: &"world", 58: &"control-flow", 60: &"inventory", 61: &"world",
	62: &"presentation", 63: &"world", 64: &"control-flow", 65: &"inventory",
	66: &"world", 67: &"inventory", 68: &"characters", 69: &"characters",
	70: &"world", 72: &"control-flow", 73: &"inventory", 76: &"control-flow",
	77: &"control-flow", 78: &"control-flow", 81: &"characters", 82: &"combat",
	83: &"combat", 84: &"control-flow", 85: &"control-flow", 86: &"control-flow",
	87: &"characters", 88: &"characters", 89: &"characters", 90: &"characters",
	91: &"inventory", 92: &"world", 93: &"world", 94: &"world", 95: &"world",
	96: &"world", 97: &"world", 98: &"control-flow", 99: &"control-flow",
	100: &"combat", 101: &"world", 102: &"characters", 103: &"world",
	104: &"world", 105: &"characters", 106: &"world", 107: &"combat",
	108: &"characters", 111: &"control-flow", 112: &"control-flow", 119: &"combat",
	120: &"combat", 121: &"combat", 122: &"combat", 123: &"combat",
	124: &"combat", 125: &"combat", 126: &"combat", 127: &"combat",
}

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
