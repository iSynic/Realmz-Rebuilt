@tool
## Supplies deterministic detached requests to production UI binders in editor previews.

class_name RealmzBuilderPreviewFixtures
extends RefCounted

const SUPPORTED_SURFACES: Array[String] = [
	"temple",
	"bank",
	"pick-lock",
	"lifecycle-prompts",
	"scrolling-text",
]


static func bind(surface: Node, surface_id: String, profile: String) -> bool:
	if surface == null or surface_id not in SUPPORTED_SURFACES or not surface.has_method("build"):
		return false
	var request := _request(surface_id, profile)
	if request == null:
		return false
	_configure(surface, surface_id, profile)
	surface.call("build", request)
	surface.set_meta("realmz_builder_profile", profile)
	return true


static func _configure(surface: Node, surface_id: String, profile: String) -> void:
	var compact := profile == "Compact"
	match surface_id:
		"temple": surface.call("configure", null, compact)
		"bank": surface.call("configure", compact)
		"pick-lock", "scrolling-text": surface.call("configure", null)


static func _request(surface_id: String, profile: String) -> InteractionRequest:
	match surface_id:
		"temple": return InteractionRequest.new("builder.temple", InteractionRequest.TEMPLE, _temple_body(profile))
		"bank": return InteractionRequest.new("builder.bank", InteractionRequest.BANK, _bank_body(profile))
		"pick-lock": return InteractionRequest.new("builder.pick-lock", InteractionRequest.PICK_LOCK, _pick_lock_body(profile))
		"lifecycle-prompts": return InteractionRequest.new("builder.lifecycle", InteractionRequest.SESSION_LIFECYCLE, _lifecycle_body(profile))
		"scrolling-text": return InteractionRequest.new("builder.scrolling-text", InteractionRequest.ACKNOWLEDGE, _scrolling_text_body(profile))
	return null


static func _temple_body(profile: String) -> InteractionRequest.TempleRequestBody:
	var body := InteractionRequest.TempleRequestBody.new()
	body.cost_percent = 115
	body.pooled_wealth = _wealth(740, 4, 1)
	body.bank_available = true
	if profile != "Empty":
		body.characters = _characters(profile, false)
		body.services = _temple_services(profile)
		body.selected_character_id = body.characters[0].id
	return body


static func _bank_body(profile: String) -> InteractionRequest.BankRequestBody:
	var body := InteractionRequest.BankRequestBody.new()
	body.mode = &"bank"
	body.has_mode = true
	body.pooled_wealth = _wealth(740, 4, 1)
	body.banked_wealth = _wealth(2800, 12, 3)
	body.pool = _availability(profile != "Unavailable", "The party cannot pool wealth during this preview state.")
	body.share = _availability(profile != "Unavailable", "No adventurer can receive a share during this preview state.")
	if profile != "Empty":
		body.characters = _characters(profile, true)
		body.selected_character_id = body.characters[0].id
	return body


static func _characters(profile: String, include_transfers: bool) -> Array[InteractionRequestValue.ServiceCharacter]:
	var names: Array[String] = ["Kevlar", "Lothlorian", "Silver Leaf", "Traskelion", "Trevor", "Vormale"]
	var count := names.size() if profile == "Long Content" else 2
	var result: Array[InteractionRequestValue.ServiceCharacter] = []
	for index: int in count:
		var character := InteractionRequestValue.ServiceCharacter.new()
		character.id = "builder.character.%d" % index
		character.name = names[index]
		character.current_health = 18 + index * 3
		character.maximum_health = 42 + index * 4
		character.personal_gold = 80 + index * 25
		character.available_gold = 0 if profile == "Unavailable" else 820 + index * 60
		character.load = 440 + index * 45
		character.maximum_load = 1800 + index * 100
		character.wealth = _wealth(character.personal_gold, index + 1, index % 2)
		if index == 0:
			character.conditions.append(_condition(6, "Poisoned", 3))
			character.conditions.append(_condition(10, "Cursed", 1))
		if include_transfers:
			character.transfers = _transfers(profile)
		result.append(character)
	return result


static func _temple_services(profile: String) -> Array[InteractionRequestValue.TempleService]:
	var labels: Array[String] = ["Heal Wounds", "Cure Poison", "Remove Curse", "Restore Life", "Purify Spirit", "Renew Strength"]
	var count := labels.size() if profile == "Long Content" else 3
	var result: Array[InteractionRequestValue.TempleService] = []
	for index: int in count:
		var service := InteractionRequestValue.TempleService.new()
		service.id = "builder.service.%d" % index
		service.label = labels[index]
		service.description = (
			"The temple attendants explain the rite, its limits, and the exact offering required before the party proceeds."
			if profile == "Long Content"
			else "A source-priced temple service for the selected adventurer."
		)
		service.cost = 9999 if profile == "Unavailable" else 75 + index * 125
		result.append(service)
	return result


static func _transfers(profile: String) -> Array[InteractionRequestValue.Transfer]:
	var result: Array[InteractionRequestValue.Transfer] = []
	for denomination: StringName in [&"gold", &"gems", &"jewelry"]:
		var transfer := InteractionRequestValue.Transfer.new()
		transfer.denomination = denomination
		transfer.amount = 100 if denomination == &"gold" else 1
		transfer.to_pool = _availability(profile != "Unavailable", "The selected wealth cannot enter the pool.")
		transfer.to_character = _availability(profile != "Unavailable", "The selected adventurer has reached the load limit.")
		result.append(transfer)
	return result


static func _pick_lock_body(profile: String) -> InteractionRequest.PickLockRequestBody:
	var body := InteractionRequest.PickLockRequestBody.new()
	body.encounter_id = 19
	body.action_index = 6
	body.action_label = "Pick Lock" if profile != "Error" else "Mechanism unavailable"
	body.character_id = "builder.character.0"
	body.character_name = "Kevlar"
	body.chance_percent = 63 if profile != "Unavailable" else 0
	body.yellow_threshold = 18
	body.green_threshold = 24
	body.frame_rate = 12
	body.time_limit_frames = 48
	var tumbler_count := 6 if profile == "Long Content" else 3
	for frame_index: int in 49:
		var frame: Array = []
		for tumbler_index: int in tumbler_count:
			frame.append(mini(28, 3 + tumbler_index * 2 + frame_index / 3))
		body.frames.append(frame)
	return body


static func _lifecycle_body(profile: String) -> InteractionRequest.LifecycleRequestBody:
	var body := InteractionRequest.LifecycleRequestBody.new()
	body.operation = &"end-adventure"
	body.prompt = "The company is about to end this adventure."
	body.has_active_session = true
	body.includes_active_session = true
	body.in_combat = profile == "Unavailable"
	if profile != "Empty":
		body.options.append(_lifecycle_option(&"save-and-end", "Save and End Adventure"))
		body.options.append(_lifecycle_option(&"end-without-saving", "End Without Saving"))
		body.options.append(_lifecycle_option(&"cancel", "Return to the Realm"))
	return body


static func _scrolling_text_body(profile: String) -> InteractionRequest.AcknowledgeBody:
	var body := InteractionRequest.AcknowledgeBody.new()
	body.presentation = &"classic-scrolling-text"
	body.has_presentation = true
	body.prompt = "" if profile == "Empty" else (
		"The archivist could not recover this account. Return when the missing volume has been restored."
		if profile == "Error"
		else "A Chronicle of the Realm\n\nThe road bends north beneath a cold and watchful moon.\n\n" + "Company records, field notes, and travelers' warnings fill the remaining pages.\n".repeat(12)
		if profile == "Long Content"
		else "A Chronicle of the Realm\n\nThe road bends north beneath a cold and watchful moon."
	)
	return body


static func _wealth(gold: int, gems: int, jewelry: int) -> InteractionRequestValue.Wealth:
	var wealth := InteractionRequestValue.Wealth.new()
	wealth.gold = gold
	wealth.gems = gems
	wealth.jewelry = jewelry
	return wealth


static func _availability(enabled: bool, reason: String) -> InteractionRequestValue.Availability:
	var availability := InteractionRequestValue.Availability.new()
	availability.enabled = enabled
	availability.reason = "" if enabled else reason
	return availability


static func _condition(index: int, label: String, value: int) -> InteractionRequestValue.Condition:
	var condition := InteractionRequestValue.Condition.new()
	condition.index = index
	condition.name = label
	condition.value = value
	return condition


static func _lifecycle_option(action: StringName, label: String) -> InteractionRequestValue.LifecycleOption:
	var option := InteractionRequestValue.LifecycleOption.new()
	option.action = action
	option.label = label
	return option
