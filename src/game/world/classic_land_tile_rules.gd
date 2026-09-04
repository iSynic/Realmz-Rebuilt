## Decodes Classic land tile values without retaining playthrough state.

class_name ClassicLandTileRules
extends RefCounted


static func normalized_tile(raw_tile: int) -> int:
	var magnitude := -raw_tile if raw_tile < 0 else raw_tile & ~0x6000
	while magnitude > 999:
		magnitude -= 1000
	return magnitude


static func special_overlay(raw_tile: int) -> String:
	if raw_tile >= 0:
		var positive_resource_id := normalized_tile(raw_tile)
		return "realmz-land-cicn-%d" % positive_resource_id if positive_resource_id > 200 else ""
	if raw_tile < -3999:
		return ""
	var resource_id := raw_tile
	for index: int in 3:
		if resource_id >= -999:
			break
		resource_id += 1000
	return "realmz-special-land-neg-%d" % absi(resource_id)
