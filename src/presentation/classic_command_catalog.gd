class_name ClassicCommandCatalog
extends RefCounted

const COMMANDS: Array[Dictionary] = [
	{"id": &"search", "asset_id": &"", "input_action": &"realmz_search", "contexts": [&"exploration"], "availability": &"search", "label": "Search", "tooltip": "Search the current area", "accelerator": "S", "focus_order": 10},
	{"id": &"camp", "asset_id": &"command.camp", "input_action": &"realmz_camp", "contexts": [&"exploration"], "availability": &"camp", "label": "Camp", "tooltip": "Make camp when the rules permit it", "accelerator": "C", "focus_order": 20},
	{"id": &"rest", "asset_id": &"command.rest", "input_action": &"realmz_rest", "contexts": [&"exploration"], "availability": &"rest", "label": "Rest", "tooltip": "Hold to rest in five-timeclick pulses", "accelerator": "R", "focus_order": 30, "hold_repeat": true},
	{"id": &"service", "asset_id": &"", "input_action": &"", "contexts": [&"exploration"], "availability": &"service_action", "label": "Service", "tooltip": "Enter the available location service", "accelerator": "", "focus_order": 40},
	{"id": &"money", "asset_id": &"command.money", "input_action": &"ui_screen_services", "contexts": [&"exploration"], "availability": &"money_action", "label": "Money", "tooltip": "Pool, share, or swap party wealth", "accelerator": "", "focus_order": 50},
	{"id": &"inventory", "asset_id": &"command.inventory", "input_action": &"ui_screen_inventory", "contexts": [&"exploration", &"character", &"inventory"], "availability": &"", "label": "Items", "tooltip": "Open party inventory", "accelerator": "I", "focus_order": 60},
	{"id": &"spells", "asset_id": &"command.spells", "input_action": &"ui_screen_spells", "contexts": [&"exploration", &"character", &"spells", &"combat"], "availability": &"", "label": "Spells", "tooltip": "Open known spells", "accelerator": "P", "focus_order": 70},
	{"id": &"maps", "asset_id": &"command.maps", "input_action": &"ui_screen_journal", "contexts": [&"exploration", &"journal"], "availability": &"", "label": "Maps", "tooltip": "Open acquired maps and notes", "accelerator": "M", "focus_order": 80},
	{"id": &"save", "asset_id": &"command.save", "input_action": &"", "contexts": [&"system"], "availability": &"", "label": "Save", "tooltip": "Quick save the active campaign", "accelerator": "", "focus_order": 70},
	{"id": &"settings", "asset_id": &"command.settings", "input_action": &"ui_screen_system", "contexts": [&"exploration", &"system"], "availability": &"", "label": "Preferences", "tooltip": "Open preferences and diagnostics", "accelerator": "", "focus_order": 90},
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
