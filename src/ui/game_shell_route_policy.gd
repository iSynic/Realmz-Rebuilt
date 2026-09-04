## Chooses automatic shell routes from detached workflow state.
class_name GameShellRoutePolicy
extends RefCounted


static func automatic_route(current_route: StringName, game_view: GameView, contextual_service_closed: bool = false) -> StringName:
	if game_view == null:
		return current_route
	if game_view.pending_interaction != null and game_view.pending_interaction.kind in [InteractionRequest.SHOP, InteractionRequest.TEMPLE, InteractionRequest.BANK]:
		return &"services"
	if game_view.combat_view != null:
		return &"combat"
	if game_view.pending_interaction != null:
		return &"exploration"
	if contextual_service_closed and current_route == &"services":
		return &"exploration"
	if game_view.combat_view == null and current_route == &"combat":
		return &"exploration"
	return current_route
