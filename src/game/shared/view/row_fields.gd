## Reads typed values out of the untyped row dictionaries that view queries hand to screens.

class_name RowFields
extends RefCounted


static func text(row: Dictionary, key: Variant, fallback: String = "") -> String:
	var value: String = row.get(key, fallback)
	return value


static func number(row: Dictionary, key: Variant, fallback: int = 0) -> int:
	var value: int = row.get(key, fallback)
	return value


static func real(row: Dictionary, key: Variant, fallback: float = 0.0) -> float:
	var value: float = row.get(key, fallback)
	return value


static func flag(row: Dictionary, key: Variant, fallback: bool = false) -> bool:
	var value: bool = row.get(key, fallback)
	return value
