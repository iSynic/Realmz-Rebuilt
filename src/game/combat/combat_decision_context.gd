## Shares read-only facts for one automatic decision; never survives an action.
class_name CombatDecisionContext
extends RefCounted

var area_centers: Dictionary = {}
var ray_actors: Dictionary = {}
var bandage_checked := false
var bandage_choice: Dictionary = {}
var _placements: Dictionary = {}
var _summons: Dictionary = {}
var _occupied: Dictionary = {}
var _occupancy_ready := false
var _spells: Array[CombatSpellAdmission] = []
var _spells_ready := false
var _threats: CombatProtectionThreats


func occupied(field: BattlefieldState) -> Dictionary:
	if not _occupancy_ready:
		for actor_id: String in field.actors.actor_ids():
			for coordinate: Vector2i in field.actors.actor_footprint(actor_id):
				_occupied[coordinate] = actor_id
		_occupancy_ready = true
	return _occupied


func character_spells(selection: CombatSpellSelection, state: GameState, content: RealmzContent, actor_id: String) -> Array[CombatSpellAdmission]:
	if not _spells_ready:
		_spells = selection.character_spell_admissions(state, content, actor_id)
		_spells_ready = true
	return _spells


func threats(state: GameState, content: RealmzContent, traitor: bool) -> CombatProtectionThreats:
	if _threats == null: _threats = CombatProtectionThreats.new(state, content, traitor)
	return _threats


func placements(source: String = "") -> Dictionary:
	# Source-specific scoring keeps its existing spell enumeration and tie order.
	if not _placements.has(source): _placements[source] = {}
	return _placements[source]


func summon_coordinates(source: String = "") -> Dictionary:
	if not _summons.has(source): _summons[source] = {}
	return _summons[source]
