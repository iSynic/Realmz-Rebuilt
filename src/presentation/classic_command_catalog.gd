class_name ClassicCommandCatalog
extends RefCounted

const COMMANDS: Array[Dictionary] = [
	{"id": &"search_mode", "group": &"world", "asset_id": &"command.search", "input_action": &"realmz_search", "contexts": [&"exploration"], "availability": &"toggle_search", "label": "Search", "tooltip": "Toggle continuous secret searching", "accelerator": "S", "focus_order": 10, "toggle_mode": true, "search_animation": true},
	{"id": &"area_search", "group": &"world", "asset_id": &"command.area_search_visual", "art_region": [10, 5, 31, 21], "input_action": &"", "contexts": [&"exploration"], "availability": &"area_search", "label": "Area Search", "tooltip": "Hold to search the nearby area", "accelerator": "", "focus_order": 15, "hold_repeat": true},
	{"id": &"torch", "group": &"world", "asset_id": &"", "input_action": &"", "contexts": [&"exploration"], "availability": &"use_torch", "label": "Torch", "tooltip": "Use the first Classic torch carried by the party", "accelerator": "T", "focus_order": 20, "torch_meter": true},
	{"id": &"camp", "group": &"world", "asset_id": &"command.camp", "art_region": [9, 3, 32, 33], "input_action": &"realmz_camp", "contexts": [&"exploration"], "availability": &"camp", "label": "Camp", "tooltip": "Make camp when the rules permit it", "accelerator": "C", "focus_order": 30},
	{"id": &"rest", "group": &"world", "asset_id": &"command.rest", "art_region": [13, 4, 23, 32], "input_action": &"realmz_rest", "contexts": [&"exploration"], "availability": &"rest", "label": "Rest", "tooltip": "Hold to rest in five-timeclick pulses", "accelerator": "R", "focus_order": 40, "hold_repeat": true},
	{"id": &"heal", "group": &"world", "asset_id": &"", "asset_path": "res://src/presentation/assets/ui/commands/heal.png", "art_region": [13, 18, 47, 40], "input_action": &"realmz_heal", "contexts": [&"exploration"], "availability": &"heal", "label": "Heal", "tooltip": "Hold to spend 10 spell points per wounded recipient", "accelerator": "H", "focus_order": 45, "hold_repeat": true},
	{"id": &"contextual", "group": &"world", "asset_id": &"command.encounter_original", "art_region": [10, 1, 31, 31], "art_mask": &"circle", "input_action": &"", "contexts": [&"exploration"], "availability": &"contextual_encounter", "label": "Encounter", "tooltip": "Open the seamless encounter at this location", "accelerator": "E", "focus_order": 50},
	{"id": &"money", "group": &"party", "asset_id": &"command.money", "art_region": [5, 5, 35, 31], "art_clear_regions": [[0, 0, 8, 8]], "input_action": &"ui_screen_services", "contexts": [&"exploration"], "availability": &"money_action", "label": "Money", "tooltip": "Pool, share, or swap party wealth", "accelerator": "", "focus_order": 60},
	{"id": &"inventory", "group": &"party", "asset_id": &"command.inventory", "art_region": [5, 2, 36, 34], "art_clear_regions": [[0, 4, 4, 8]], "input_action": &"ui_screen_inventory", "contexts": [&"exploration", &"character", &"inventory"], "availability": &"", "label": "Items", "tooltip": "Open party inventory", "accelerator": "I", "focus_order": 70},
	{"id": &"spells", "group": &"party", "asset_id": &"command.spells", "art_region": [5, 3, 37, 33], "art_clear_regions": [[0, 2, 6, 8]], "input_action": &"ui_screen_spells", "contexts": [&"exploration", &"character", &"spells", &"combat"], "availability": &"", "label": "Spells", "tooltip": "Open known spells", "accelerator": "P", "focus_order": 80},
	{"id": &"maps", "group": &"party", "asset_id": &"command.maps", "art_region": [8, 5, 34, 31], "input_action": &"ui_screen_journal", "contexts": [&"exploration", &"journal"], "availability": &"", "label": "Maps", "tooltip": "Open acquired maps and notes", "accelerator": "M", "focus_order": 90},
	{"id": &"save", "asset_id": &"command.save", "input_action": &"", "contexts": [&"system"], "availability": &"", "label": "Save", "tooltip": "Quick save the active campaign", "accelerator": "", "focus_order": 70},
	{"id": &"settings", "group": &"world", "asset_id": &"command.settings", "art_region": [10, 9, 29, 26], "input_action": &"ui_screen_system", "contexts": [&"exploration", &"system"], "availability": &"", "label": "Settings", "tooltip": "Open preferences and diagnostics", "accelerator": "", "focus_order": 100},
	{"id": &"encounter_action", "asset_id": &"encounter.action", "input_action": &"", "contexts": [&"encounter"], "availability": &"", "label": "Action", "tooltip": "Use a scenario action", "accelerator": "", "focus_order": 100},
	{"id": &"encounter_items", "asset_id": &"encounter.items", "input_action": &"", "contexts": [&"encounter"], "availability": &"", "label": "Items", "tooltip": "Use an item in this encounter", "accelerator": "", "focus_order": 110},
	{"id": &"encounter_skills", "asset_id": &"encounter.skills", "input_action": &"", "contexts": [&"encounter"], "availability": &"", "label": "Skills", "tooltip": "Use an available skill", "accelerator": "", "focus_order": 120},
	{"id": &"encounter_speak", "asset_id": &"encounter.speak", "input_action": &"", "contexts": [&"encounter"], "availability": &"", "label": "Speak", "tooltip": "Speak during this encounter", "accelerator": "", "focus_order": 130},
	{"id": &"encounter_stop", "asset_id": &"encounter.stop", "input_action": &"realmz_back", "contexts": [&"encounter"], "availability": &"", "label": "Stop", "tooltip": "Leave this encounter when allowed", "accelerator": "Esc", "focus_order": 140},
]


static func command(command_id: StringName) -> Dictionary:
	for definition: Dictionary in COMMANDS:
		if definition["id"] == command_id:
			return definition
	return {}


static func for_context(context: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in COMMANDS:
		if context in definition["contexts"]:
			result.append(definition)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left["focus_order"]) < int(right["focus_order"]))
	return result
