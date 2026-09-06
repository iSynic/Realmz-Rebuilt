## Composes application and scenario media without erasing source ownership.

class_name PackageMediaComposer
extends RefCounted


static func compose(scenario_assets: Array[MediaAsset], application_assets: Array[MediaAsset]) -> Array[MediaAsset]:
	var effective: Array[MediaAsset] = scenario_assets.duplicate()
	var scenario_keys: Dictionary = {}
	var scenario_ids: Dictionary = {}
	for asset: MediaAsset in scenario_assets:
		scenario_keys[_overlay_key(asset)] = true
		scenario_ids[asset.id] = true
	for asset: MediaAsset in application_assets:
		if not scenario_keys.has(_overlay_key(asset)) and not scenario_ids.has(asset.id):
			effective.append(asset)
	return effective


static func _overlay_key(asset: MediaAsset) -> String:
	if not asset.resource_type.is_empty():
		return JSON.stringify([asset.resource_type, asset.resource_id])
	return JSON.stringify(["asset", asset.id])
