## Carries one detached Treasure distribution or recovery operation.

class_name TreasureRequestBody
extends InteractionRequestBody

var mode: StringName
var prompt: String
var item: InteractionRequestValue.RewardItem
var items: Array[InteractionRequestValue.RewardItem] = []
var remaining: int
var characters: Array[InteractionRequestValue.RewardCharacter] = []
var wealth: InteractionRequestValue.Wealth
var experience_share: int
var detect: InteractionRequestValue.RewardMethod
var identify: InteractionRequestValue.RewardMethod
var has_share_capacity: bool
var summary: String
var battle_id: String
var origin: StringName
var source_id: String
var experience_pool: int
var has_item: bool
var has_items: bool
var has_remaining: bool


func to_data() -> Dictionary:
	var data := {"mode": String(mode)}
	if not prompt.is_empty(): data["prompt"] = prompt
	if has_item: data["item"] = null if item == null else item.to_data()
	if has_items: data["items"] = items.map(func(value: InteractionRequestValue.RewardItem) -> Dictionary: return value.to_data())
	if has_remaining: data["remaining"] = remaining
	if not characters.is_empty(): data["characters"] = characters.map(func(value: InteractionRequestValue.RewardCharacter) -> Dictionary: return value.to_data())
	if wealth != null: data["wealth"] = wealth.to_data()
	if experience_share != 0: data["experienceShare"] = experience_share
	if detect != null: data["detect"] = detect.to_data()
	if identify != null: data["identify"] = identify.to_data()
	if has_share_capacity: data["hasShareCapacity"] = true
	if not summary.is_empty(): data["summary"] = summary
	if not battle_id.is_empty(): data["battleId"] = battle_id
	if not origin.is_empty(): data["origin"] = String(origin)
	if not source_id.is_empty(): data["sourceId"] = source_id
	if experience_pool != 0: data["experiencePool"] = experience_pool
	return data


func prompt_text() -> String:
	return prompt


func same_fumble_values(other: TreasureRequestBody) -> bool:
	if other == null or mode != &"fumbled-item-recovery" or other.mode != mode \
			or prompt != other.prompt or battle_id != other.battle_id \
			or not has_item or not other.has_item or not has_remaining or not other.has_remaining \
			or remaining != other.remaining or item == null or other.item == null \
			or characters.size() != other.characters.size():
		return false
	if item.to_data() != other.item.to_data():
		return false
	for index: int in characters.size():
		var left := characters[index]
		var right := other.characters[index]
		if left.id != right.id or left.name != right.name or left.enabled != right.enabled \
				or left.reason != right.reason or left.has_health != right.has_health \
				or not left.has_health or not right.has_health \
				or left.current_health != right.current_health or left.maximum_health != right.maximum_health:
			return false
	return true
