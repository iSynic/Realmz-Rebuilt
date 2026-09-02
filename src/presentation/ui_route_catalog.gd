class_name UiRouteCatalog
extends RefCounted

const ROUTES: Array[Dictionary] = [
	{"id": &"exploration", "label": "Explore", "shortcut": "ui_screen_explore", "primary": true, "description": "Move, search, camp, and follow the scenario.", "scene": "res://src/presentation/screens/exploration_screen.tscn"},
	{"id": &"character", "label": "Characters", "shortcut": "ui_screen_characters", "primary": true, "description": "Inspect statistics, conditions, allies, and equipment.", "scene": "res://src/presentation/screens/character_screen.tscn"},
	{"id": &"allies", "label": "Allies", "shortcut": "", "primary": false, "description": "Inspect the monsters currently traveling with the party.", "scene": "res://src/presentation/screens/allies_screen.tscn"},
	{"id": &"bestiary", "label": "Bestiary", "shortcut": "", "primary": false, "description": "Browse the active Classic monster catalog.", "scene": "res://src/presentation/screens/bestiary_screen.tscn"},
	{"id": &"vault", "label": "Vault", "shortcut": "ui_screen_vault", "primary": false, "description": "Import and review reusable character revisions.", "scene": "res://src/presentation/screens/vault_screen.tscn"},
	{"id": &"inventory", "label": "Inventory", "shortcut": "ui_screen_inventory", "primary": true, "description": "Equip, identify, use, trade, and store items.", "scene": "res://src/presentation/screens/inventory_screen.tscn"},
	{"id": &"spells", "label": "Spells", "shortcut": "ui_screen_spells", "primary": true, "description": "Review known spells, powers, costs, and targets.", "scene": "res://src/presentation/screens/spells_screen.tscn"},
	{"id": &"services", "label": "Money", "shortcut": "ui_screen_services", "primary": false, "description": "Pool, share, and exchange party wealth.", "scene": "res://src/presentation/screens/services_screen.tscn"},
	{"id": &"combat", "label": "Battle", "shortcut": "ui_screen_battle", "primary": false, "description": "Choose actors, targets, and legal combat actions.", "scene": "res://src/presentation/screens/combat_screen.tscn"},
	{"id": &"journal", "label": "Journal", "shortcut": "ui_screen_journal", "primary": true, "description": "Review maps, notes, history, and campaign state.", "scene": "res://src/presentation/screens/journal_screen.tscn"},
	{"id": &"system", "label": "System", "shortcut": "ui_screen_system", "primary": true, "description": "Save, load, settings, and readiness diagnostics.", "scene": "res://src/presentation/screens/system_screen.tscn"},
]


static func route(route_id: StringName) -> Dictionary:
	for definition: Dictionary in ROUTES:
		if definition["id"] == route_id:
			return definition
	return {}


static func has_route(route_id: StringName) -> bool:
	return not UiRouteCatalog.route(route_id).is_empty()
