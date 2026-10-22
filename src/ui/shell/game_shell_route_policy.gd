## Chooses automatic shell routes from detached workflow state.
class_name GameShellRoutePolicy
extends RefCounted


static func automatic_route(current_route: StringName, game_view: GameView, contextual_service_closed: bool = false) -> StringName:
	if game_view == null:
		return current_route
	if game_view.pending_interaction != null and game_view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK]:
		return &"services"
	if game_view.combat_view != null:
		# The full Inventory workspace is a modal combat surface. Keep it mounted
		# while the active battle request is rebuilt after an item mutation.
		return current_route if current_route in [&"inventory", &"system"] else &"combat"
	if game_view.pending_interaction != null:
		return &"exploration"
	if contextual_service_closed and current_route == &"services":
		return &"exploration"
	if game_view.combat_view == null and current_route == &"combat":
		return &"exploration"
	return current_route


static func playback_base_route(current_route: StringName, game_view: GameView) -> StringName:
	if current_route in [&"inventory", &"system"]:
		return current_route
	if game_view != null and game_view.combat_view != null and game_view.combat_view.battlefield != null:
		return &"combat"
	return current_route


static func combat_workspace_owns_interaction(active_route: StringName, game_view: GameView) -> bool:
	return active_route in [&"inventory", &"system"] and game_view != null and game_view.combat_view != null and game_view.combat_view.outcome == &"active"

static func dungeon_view_toggle_available(map_view: MapView) -> bool:
	return map_view != null and map_view.level_type == &"dungeon" and (map_view.dungeon_multiview or map_view.wizard_eye_active)


static func should_show_exploration_stage(active_route: StringName, game_view: GameView, play_stage_visible: bool) -> bool:
	return active_route in [&"exploration", &"spells", &"save_load"] and game_view != null and game_view.session_started and not game_view.party_setup_available and (active_route != &"save_load" or game_view.combat_view == null) and play_stage_visible


static func should_show_spatial_stage(active_route: StringName, game_view: GameView, play_stage_visible: bool) -> bool:
	return should_show_exploration_stage(active_route, game_view, play_stage_visible)


static func should_show_battle_stage(active_route: StringName, game_view: GameView, play_stage_visible: bool) -> bool:
	return active_route in [&"combat", &"save_load"] and game_view != null and game_view.session_started and game_view.combat_view != null and game_view.combat_view.battlefield != null and play_stage_visible
