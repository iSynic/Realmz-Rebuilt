## Creates typed commands for travel, field actions, and player-authored map notes.

class_name ExplorationIntents
extends RefCounted


static func move(direction: Vector2i) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.MOVE, ExplorationIntentPayloads.Move.new(direction))


static func overhead_dungeon_move(direction: Vector2i) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.MOVE, ExplorationIntentPayloads.Move.new(direction, true))


static func dungeon_turn(delta: int) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.DUNGEON_TURN, ExplorationIntentPayloads.DungeonTurn.new(delta))


static func search() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SEARCH)


static func toggle_search() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.TOGGLE_SEARCH)


static func use_torch() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.USE_TORCH)


static func contextual_encounter() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CONTEXTUAL_ENCOUNTER)


static func camp() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAMP)


static func rest() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.REST)


static func heal() -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.HEAL)


static func set_location_note(text: String) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SET_LOCATION_NOTE, ExplorationIntentPayloads.LocationNote.new(text))
