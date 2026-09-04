## Carries the detached temple services, characters, wealth, and actions.

class_name TempleRequestBody
extends ServiceRequestBody

var cost_percent: int
var services: Array[InteractionRequestValue.TempleService] = []
var pooled_wealth: InteractionRequestValue.Wealth
var bank_available: bool
var selected_character_id: String


func to_data() -> Dictionary:
	return {"costPercent": cost_percent, "characters": characters.map(func(value: InteractionRequestValue.ServiceCharacter) -> Dictionary: return value.to_temple_data()), "services": services.map(func(value: InteractionRequestValue.TempleService) -> Dictionary: return value.to_data()), "pooledWealth": pooled_wealth.to_data(), "bankAvailable": bank_available, "selectedCharacterId": selected_character_id, "actions": actions.duplicate()}
