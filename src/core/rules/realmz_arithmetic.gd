class_name RealmzArithmetic
extends RefCounted


func signed_16(value: int) -> int:
	var wrapped := value & 0xffff
	return wrapped - 0x10000 if wrapped >= 0x8000 else wrapped


func unsigned_16(value: int) -> int:
	return value & 0xffff


func signed_32(value: int) -> int:
	var wrapped := value & 0xffffffff
	return wrapped - 0x1_0000_0000 if wrapped >= 0x8000_0000 else wrapped


func percentage_succeeds(roll: int, chance: int, inclusive: bool = true) -> bool:
	return roll <= chance if inclusive else roll < chance


func pin(value: int, minimum: int, maximum: int) -> int:
	return clampi(value, minimum, maximum)
