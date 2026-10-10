## Retains detached map crops while their authoritative cell dependencies are unchanged.
class_name SessionMapPreviewCache
extends RefCounted

var _world: WorldState
var _topology_revision: int = -1
var _bounds_revision: int = -1
var _exploration_revision: int = -1
var _visited_by_map: Dictionary = {}
var _player_maps: Dictionary = {}
var _notes: Dictionary = {}
var _player_map_visits: Dictionary = {}
var _note_visits: Dictionary = {}


func prepare(context: SessionWorkflowContext) -> void:
	var world := context.state.world
	if _world != world:
		_topology_revision = -1
		_exploration_revision = -1
		_world = world
	if _topology_revision != world.topology.revision() or _bounds_revision != world.triggers.random_region_bounds_revision():
		_player_maps.clear()
		_notes.clear()
		_player_map_visits.clear()
		_note_visits.clear()
		_topology_revision = world.topology.revision()
		_bounds_revision = world.triggers.random_region_bounds_revision()
	if _exploration_revision != world.exploration.revision():
		_visited_by_map.clear()
		_exploration_revision = world.exploration.revision()
	for note_id: String in _notes.keys():
		var preview := _notes[note_id] as MapView
		if world.exploration.location_note_at(preview.map_id, preview.party_coordinate) == null:
			_notes.erase(note_id)
			_note_visits.erase(note_id)


func player_map(context: SessionWorkflowContext, definition: PlayerMapDefinition) -> PlayerMapView:
	var visited := _visited(context, definition.map_id)
	var cached := _player_maps.get(definition.id) as PlayerMapView
	if cached == null or _player_map_visits.get(definition.id) != visited:
		cached = SessionMapViewBuilder.build_player_map_view(context, definition)
		_player_maps[definition.id] = cached
		_player_map_visits[definition.id] = visited
	var map := context.content.world.map_by_id(definition.map_id)
	var party := context.state.party
	return PlayerMapView.new(definition, cached.cells, SessionMapViewBuilder.player_map_shows_party(definition, map, party.map_id, party.coordinate), party.coordinate, true)


func location_note(context: SessionWorkflowContext, map: MapDefinition, note: LocationNoteState) -> MapView:
	var visited := _visited(context, map.id)
	var cached := _notes.get(note.id()) as MapView
	if cached == null or _note_visits.get(note.id()) != visited or cached.darkness_level != clampi(note.darkness_value, 0, 6):
		cached = SessionMapViewBuilder.build_location_note_map_view(context, map, note)
		_notes[note.id()] = cached
		_note_visits[note.id()] = visited
	return cached


func _visited(context: SessionWorkflowContext, map_id: String) -> Array[Vector2i]:
	if not _visited_by_map.has(map_id):
		_visited_by_map[map_id] = context.state.world.exploration.visited_coordinates(map_id)
	return _visited_by_map[map_id]
