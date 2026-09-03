class_name MediaSource
extends RefCounted


func assets() -> Array[MediaAsset]:
	return []


func assets_of_kind(_kind: String) -> Array[MediaAsset]:
	return []


func asset_by_id(_asset_id: String) -> MediaAsset:
	return null


func asset_by_resource(_resource_type: String, _resource_id: int) -> MediaAsset:
	return null


func resource_status(_resource_type: String, _resource_id: int) -> StringName:
	return &"missing"


func resolution_diagnostic(_resource_type: String, _resource_id: int, _presentation_role: String, _decode_result: String = "not-attempted") -> Dictionary:
	return {}


func owns_asset(_asset: MediaAsset) -> bool:
	return false


func read_bytes(_asset: MediaAsset) -> PackedByteArray:
	return PackedByteArray()


func read_bytes_batch(requested_assets: Array[MediaAsset]) -> Dictionary:
	var result: Dictionary = {}
	for asset: MediaAsset in requested_assets:
		result[asset.id] = read_bytes(asset)
	return result
