## Builds ordinary Treasure requests, decoding each item payload with the same
## strict decoder but reusing the previous request's decoded item when its
## payload is exactly unchanged. Decoded items are never mutated by consumers.
class_name ClassicTreasureRequestCache
extends RefCounted

var _sources: Dictionary[String, Dictionary] = {}
var _decoded: Dictionary[String, InteractionRequestValue.RewardItem] = {}


## Returns null when the payload or any item fails strict decoding.
func request(request_id: String, item_payloads: Array[Dictionary], payload: Dictionary) -> InteractionRequest:
	var sources: Dictionary[String, Dictionary] = {}
	var decoded: Dictionary[String, InteractionRequestValue.RewardItem] = {}
	var items: Array[InteractionRequestValue.RewardItem] = []
	for item_payload: Dictionary in item_payloads:
		var instance_id: String = item_payload.get("instanceId", "")
		var unchanged := _sources.has(instance_id) and _sources[instance_id] == item_payload
		var item: InteractionRequestValue.RewardItem = _decoded[instance_id] if unchanged else InteractionRewardValueDecoder.reward_item(item_payload)
		if item == null:
			return null
		sources[instance_id] = item_payload
		decoded[instance_id] = item
		items.append(item)
	var full := payload.duplicate()
	full["items"] = []
	var result := InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, full)
	if result == null:
		return null
	(result.body as TreasureRequestBody).items = items
	_sources = sources
	_decoded = decoded
	return result
