## Composes application and scenario media without erasing source ownership.

class_name PackageMediaComposer
extends RefCounted


static func compose(scenario_assets: Array[MediaAsset], application_assets: Array[MediaAsset]) -> Array[MediaAsset]:
	var effective: Array[MediaAsset] = scenario_assets.duplicate()
	var scenario_keys: Dictionary = {}
	for asset: MediaAsset in scenario_assets:
		if not asset.resource_type.is_empty():
			scenario_keys[_resource_key(asset)] = true
	for asset: MediaAsset in application_assets:
		if asset.resource_type.is_empty() or not scenario_keys.has(_resource_key(asset)):
			effective.append(asset)
	return effective


static func _resource_key(asset: MediaAsset) -> String:
	return JSON.stringify([asset.resource_type, asset.resource_id])
