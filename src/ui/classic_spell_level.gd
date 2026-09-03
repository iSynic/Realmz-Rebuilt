class_name ClassicSpellLevel
extends RefCounted


static func from_classic_id(classic_id: int) -> int:
	if classic_id < 1101:
		return 1
	return clampi(int(classic_id % 1000 / 100), 1, 7)
