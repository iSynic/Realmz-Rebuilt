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
		return current_route if current_route == &"inventory" else &"combat"
	if game_view.pending_interaction != null:
		return &"exploration"
	if contextual_service_closed and current_route == &"services":
		return &"exploration"
	if game_view.combat_view == null and current_route == &"combat":
		return &"exploration"
	return current_route


static func playback_base_route(current_route: StringName, game_view: GameView) -> StringName:
	if game_view != null and game_view.combat_view != null and game_view.combat_view.battlefield != null:
		return &"combat"
	return current_route


static func combat_inventory_owns_interaction(active_route: StringName, game_view: GameView) -> bool:
	return active_route == &"inventory" and game_view != null and game_view.combat_view != null and game_view.combat_view.outcome == &"active"
