class_name ViewDomainRevisions
extends RefCounted

var party: int = 0
var setup: int = 0
var exploration: int = 0
var inventory_magic: int = 0
var services: int = 0
var combat: int = 0
var system: int = 0


static func all_at(revision: int) -> ViewDomainRevisions:
	var result := ViewDomainRevisions.new()
	result.party = revision
	result.setup = revision
	result.exploration = revision
	result.inventory_magic = revision
	result.services = revision
	result.combat = revision
	result.system = revision
	return result


func movement_update(revision: int) -> ViewDomainRevisions:
	var result := duplicate_revisions()
	result.exploration = revision
	result.system = revision
	return result


func duplicate_revisions() -> ViewDomainRevisions:
	var result := ViewDomainRevisions.new()
	result.party = party
	result.setup = setup
	result.exploration = exploration
	result.inventory_magic = inventory_magic
	result.services = services
	result.combat = combat
	result.system = system
	return result


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


func is_ordinary_exploration_update_from(previous: ViewDomainRevisions) -> bool:
	return previous != null \
		and exploration != previous.exploration \
		and party == previous.party \
		and setup == previous.setup \
		and inventory_magic == previous.inventory_magic \
		and services == previous.services \
		and combat == previous.combat
