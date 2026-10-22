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
		var positive_resource_id := raw_tile & ~0x6000
		for index: int in 3:
			if positive_resource_id <= 999:
				break
			positive_resource_id -= 1000
		return "realmz-land-cicn-%d" % positive_resource_id if positive_resource_id > 200 else ""
	# Castle centerpict applies one signed adjustment, independently of movement.
	var resource_id := raw_tile + (2000 if raw_tile < -1999 else 1000 if raw_tile < -999 else 0)
	return "realmz-special-land-neg-%d" % absi(resource_id)


static func player_map_overlay(raw_tile: int) -> String:
	if raw_tile >= 0:
		return ""
	var resource_id := raw_tile
	for index: int in 3:
		if resource_id < -999:
			resource_id += 1000
	return "realmz-special-land-neg-%d" % absi(resource_id)
