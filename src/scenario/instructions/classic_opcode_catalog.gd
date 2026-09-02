class_name ClassicOpcodeCatalog
extends RefCounted

const DISPOSITION_EXECUTABLE: StringName = &"executable"
const DISPOSITION_CLASSIC_RESERVED: StringName = &"classic-reserved"
const DISPOSITION_PENDING: StringName = &"unsupported-pending"
const DISPOSITION_UNKNOWN: StringName = &"unknown"

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
	0: &"classic-reserved", 41: &"encounters", 44: &"encounters", 53: &"character",
	55: &"character", 57: &"world-time", 58: &"control-flow", 59: &"control-flow",
	67: &"inventory-economy", 68: &"world-time", 70: &"world-time", 71: &"presentation",
	72: &"control-flow", 74: &"character", 75: &"character", 78: &"world-time",
	79: &"classic-reserved", 80: &"classic-reserved", 81: &"character", 84: &"control-flow",
	85: &"control-flow", 92: &"world-time", 93: &"presentation", 94: &"presentation",
	95: &"world-time", 96: &"presentation", 97: &"presentation", 100: &"combat-rewards",
	109: &"classic-reserved", 110: &"classic-reserved", 113: &"classic-reserved", 114: &"classic-reserved",
	115: &"classic-reserved", 116: &"classic-reserved", 117: &"classic-reserved", 118: &"classic-reserved",
	125: &"combat-rewards",
}

const VM_CONTROL_FLOW_OPCODES: Array[int] = [39, 111, 112]

const EXECUTABLE_OPCODES: Array[int] = [
	-23, -14,
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
	20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 35, 36, 37, 38, 39,
	34, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 52, 54, 56, 88, 89, 98, 99, 104, 107,
	50, 53, 55, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 81, 82, 83, 84, 85, 86, 87, 90, 91, 92, 93, 94, 95, 96, 97, 100, 101, 102, 103, 105, 106, 108, 111, 112, 119, 120, 121, 122, 123, 124, 125, 126, 127,
]

const CLASSIC_RESERVED_OPCODES: Array[int] = [
	0, 79, 80, 109, 110, 113, 114, 115, 116, 117, 118,
]

const PENDING_OPCODES: Array[int] = []


static func normalize(raw_opcode: int) -> int:
	return -raw_opcode if raw_opcode < 0 and raw_opcode not in [-14, -23] else raw_opcode


static func owner(opcode: int) -> StringName:
	return OWNER_BY_OPCODE.get(normalize(opcode), &"") as StringName


static func is_owned(opcode: int) -> bool:
	return not owner(opcode).is_empty()


static func is_executable(opcode: int) -> bool:
	return EXECUTABLE_OPCODES.has(normalize(opcode))


static func disposition(raw_opcode: int) -> StringName:
	var opcode := normalize(raw_opcode)
	if EXECUTABLE_OPCODES.has(opcode):
		return DISPOSITION_EXECUTABLE
	if CLASSIC_RESERVED_OPCODES.has(opcode):
		return DISPOSITION_CLASSIC_RESERVED
	if PENDING_OPCODES.has(opcode):
		return DISPOSITION_PENDING
	return DISPOSITION_UNKNOWN


static func has_final_disposition(raw_opcode: int) -> bool:
	return disposition(raw_opcode) in [DISPOSITION_EXECUTABLE, DISPOSITION_CLASSIC_RESERVED]


static func evidence_reference(raw_opcode: int) -> String:
	var opcode := normalize(raw_opcode)
	match disposition(opcode):
		DISPOSITION_EXECUTABLE:
			return "runtime-handler:%s" % owner(opcode)
		DISPOSITION_CLASSIC_RESERVED:
			return "divinity-manual:empty" if opcode == 0 else "divinity-manual:not-used"
		DISPOSITION_PENDING:
			return "pending-source-adjudication"
	return ""


static func classic_opcode_identities() -> Array[int]:
	var result: Array[int] = [-23, -14]
	for opcode: int in range(128):
		result.append(opcode)
	return result


static func parity_summary() -> Dictionary:
	var result := {"classicReserved": 0, "executable": 0, "missingEvidence": 0, "pending": 0, "total": 0, "unowned": 0, "unknown": 0}
	for opcode: int in classic_opcode_identities():
		result["total"] += 1
		result["unowned"] += 1 if owner(opcode).is_empty() else 0
		result["missingEvidence"] += 1 if evidence_reference(opcode).is_empty() else 0
		match disposition(opcode):
			DISPOSITION_EXECUTABLE: result["executable"] += 1
			DISPOSITION_CLASSIC_RESERVED: result["classicReserved"] += 1
			DISPOSITION_PENDING: result["pending"] += 1
			_: result["unknown"] += 1
	return result


static func runtime_handler_opcodes() -> Array[int]:
	var result: Array[int] = []
	for opcode: int in EXECUTABLE_OPCODES:
		if not VM_CONTROL_FLOW_OPCODES.has(opcode):
			result.append(opcode)
	result.sort()
	return result
