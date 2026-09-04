## Carries the detached pooled, banked, and character wealth workspace.

class_name BankRequestBody
extends ServiceRequestBody

var mode: StringName
var has_mode: bool
var selected_character_id: String
var pooled_wealth: InteractionRequestValue.Wealth
var banked_wealth: InteractionRequestValue.Wealth
var pool: InteractionRequestValue.Availability
var share: InteractionRequestValue.Availability


func to_data() -> Dictionary:
	var data := {"selectedCharacterId": selected_character_id, "pooledWealth": pooled_wealth.to_data(), "bankedWealth": banked_wealth.to_data(), "pool": pool.to_data(), "share": share.to_data(), "characters": characters.map(func(value: InteractionRequestValue.ServiceCharacter) -> Dictionary: return value.to_bank_data())}
	if has_mode: data["mode"] = String(mode)
	if not actions.is_empty(): data["actions"] = actions.duplicate()
	return data
