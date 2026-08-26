class_name ClassicMusicContext
extends RefCounted

const CONTEXT_NAMES: Array[String] = [
	"Outdoor", "Dungeon", "Indoor", "Cave", "Create", "Items", "Treasure", "Shop", "Camp", "Temple",
	"Battle", "Desert", "Swamp", "Snow", "Custom 1", "Custom 2", "Custom 3", "Unused 18", "Unused 19", "Unused 20",
]


static func playlist_for(route_id: StringName, view: GameView) -> int:
	if view == null or not view.session_started or view.party_setup_available:
		return 0
	var interaction := view.active_interaction_request()
	if interaction != null:
		match interaction.kind:
			InteractionRequest.COMBAT: return 11
			InteractionRequest.TREASURE_DISTRIBUTION: return 7
			InteractionRequest.SHOP: return 8
			InteractionRequest.TEMPLE: return 10
	if view.combat_view != null or route_id == &"combat":
		return 11
	if view.character_draft != null:
		return 5
	if route_id == &"inventory":
		return 6
	if view.party_summary != null and view.party_summary.camping:
		return 9
	if view.map_view == null:
		return 0
	if view.map_view.level_type == &"dungeon":
		return 2
	if view.map_view.base_scale > 0:
		return 3
	match view.map_view.landlook:
		3: return 4
		5: return 12
		6: return 15
		7: return 16
		8: return 17
		9: return 13
		10: return 14
	return 1


static func context_name(playlist_id: int) -> String:
	return CONTEXT_NAMES[playlist_id - 1] if playlist_id >= 1 and playlist_id <= CONTEXT_NAMES.size() else "No music context"
