class_name ViewDomainRevisions
extends RefCounted

var party: int = 0
var setup: int = 0
var exploration: int = 0
var inventory_magic: int = 0
var services: int = 0
var combat: int = 0
var system: int = 0


func _init(revision: int = 0) -> void:
	party = revision
	setup = revision
	exploration = revision
	inventory_magic = revision
	services = revision
	combat = revision
	system = revision


func route_revision(route_id: StringName) -> int:
	match route_id:
		&"campaigns", &"party_setup", &"vault": return setup
		&"character": return party
		&"inventory", &"spells": return inventory_magic
		&"services": return services
		&"combat": return combat
		&"maps_journal", &"exploration": return exploration
		&"system": return system
	return int([party, setup, exploration, inventory_magic, services, combat, system].max())


func is_ordinary_exploration_update_from(previous: RefCounted) -> bool:
	return previous != null \
		and exploration != previous.exploration \
		and party == previous.party \
		and setup == previous.setup \
		and inventory_magic == previous.inventory_magic \
		and services == previous.services \
		and combat == previous.combat
