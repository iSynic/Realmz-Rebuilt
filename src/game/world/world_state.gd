## Groups the mutable topology, trigger, and exploration state for one playthrough.

class_name WorldState
extends RefCounted

var topology: WorldTopologyState
var triggers: WorldTriggerState
var exploration: WorldExplorationState


func _init(topology_state: WorldTopologyState = null, trigger_state: WorldTriggerState = null, exploration_state: WorldExplorationState = null) -> void:
	topology = topology_state if topology_state != null else WorldTopologyState.new()
	triggers = trigger_state if trigger_state != null else WorldTriggerState.new()
	exploration = exploration_state if exploration_state != null else WorldExplorationState.new()


func to_data() -> Dictionary:
	var topology_data := topology.to_data()
	var trigger_data := triggers.to_data()
	var exploration_data := exploration.to_data()
	return {
		"terrainOverrides": topology_data["terrainOverrides"],
		"boatPresenceOverrides": topology_data["boatPresenceOverrides"],
		"doorStates": topology_data["doorStates"],
		"discoveredSecrets": topology_data["discoveredSecrets"],
		"disabledTriggers": trigger_data["disabledTriggers"],
		"visitedCells": exploration_data["visitedCells"],
		"seenCells": exploration_data["seenCells"],
		"triggerChances": trigger_data["triggerChances"],
		"acquiredMaps": exploration_data["acquiredMaps"],
		"randomRegions": trigger_data["randomRegions"],
		"mapDarkness": topology_data["mapDarkness"],
		"mapLandlooks": topology_data["mapLandlooks"],
		"locationNotes": exploration_data["locationNotes"],
	}


static func from_data(data: Variant) -> WorldState:
	if not data is Dictionary:
		return null
	var topology_state := WorldTopologyState.from_data(data)
	var trigger_state := WorldTriggerState.from_data(data)
	var exploration_state := WorldExplorationState.from_data(data)
	if topology_state == null or trigger_state == null or exploration_state == null:
		return null
	return WorldState.new(topology_state, trigger_state, exploration_state)
