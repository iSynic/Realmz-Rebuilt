## Presents editor-authored UI route definitions through the Godot interface.

class_name UiRouteCatalog
extends RefCounted

const ROUTE_RESOURCE_PATHS: PackedStringArray = [
	"res://src/ui/shell/routes/exploration.tres",
	"res://src/ui/shell/routes/character.tres",
	"res://src/ui/shell/routes/allies.tres",
	"res://src/ui/shell/routes/bestiary.tres",
	"res://src/ui/shell/routes/vault.tres",
	"res://src/ui/shell/routes/inventory.tres",
	"res://src/ui/shell/routes/spells.tres",
	"res://src/ui/shell/routes/services.tres",
	"res://src/ui/shell/routes/combat.tres",
	"res://src/ui/shell/routes/journal.tres",
	"res://src/ui/shell/routes/system.tres",
]

static var _routes: Array[UiRouteDefinition] = []


static func routes() -> Array[UiRouteDefinition]:
	if _routes.is_empty():
		for path: String in ROUTE_RESOURCE_PATHS:
			var definition := load(path) as UiRouteDefinition
			assert(definition != null, "Invalid UI route resource: %s" % path)
			_routes.append(definition)
	return _routes


static func route(route_id: StringName) -> UiRouteDefinition:
	for definition: UiRouteDefinition in routes():
		if definition.route_id == route_id:
			return definition
	return null


static func has_route(route_id: StringName) -> bool:
	return UiRouteCatalog.route(route_id) != null
