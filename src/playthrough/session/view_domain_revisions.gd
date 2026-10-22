## Carries typed view domain revisions data across the gameplay transaction boundary.

class_name ViewDomainRevisions
extends RefCounted

var party: int = 0
var party_roster: int = 0
var party_status: int = 0
var setup: int = 0
var exploration: int = 0
var inventory_magic: int = 0
var inventory: int = 0
var magic: int = 0
var services: int = 0
var combat: int = 0
var system: int = 0


func _init(revision: int = 0) -> void:
	party = revision
	party_roster = revision
	party_status = revision
	setup = revision
	exploration = revision
	inventory_magic = revision
	inventory = revision
	magic = revision
	services = revision
	combat = revision
	system = revision


func route_revision(route_id: StringName) -> int:
	match route_id:
		&"campaigns", &"party_setup", &"vault": return setup
		&"character": return maxi(party_roster, party_status)
		&"inventory": return maxi(party_roster, inventory)
		&"spells": return maxi(party_roster, maxi(party_status, magic))
		&"services": return services
		&"combat": return combat
		&"maps_journal", &"exploration": return exploration
		&"system": return system
	var highest: int = [party_roster, party_status, setup, exploration, inventory, magic, services, combat, system].max()
	return highest


func is_ordinary_exploration_update_from(previous: RefCounted) -> bool:
	if previous == null:
		return false
	var prior: ViewDomainRevisions = previous
	return exploration != prior.exploration \
		and party_roster == prior.party_roster \
		and (party_status == prior.party_status or party_status == exploration) \
		and setup == prior.setup \
		and (inventory == prior.inventory or inventory == exploration) \
		and (magic == prior.magic or magic == exploration) \
		and services == prior.services \
		and combat == prior.combat


func synchronize_legacy_aggregates() -> void:
	party = maxi(party_roster, party_status)
	inventory_magic = maxi(inventory, magic)
