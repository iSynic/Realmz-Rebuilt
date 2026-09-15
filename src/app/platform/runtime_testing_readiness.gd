## Builds the detached application-readiness record for opt-in runtime testing.
class_name RuntimeTestingReadiness
extends RefCounted


static func fields(application: RealmzApplication, session: GameSessionController, presentation: PresentationCoordinator, lifecycle: ApplicationLifecycleHost, persistent_auto: RefCounted) -> Dictionary:
	var presentation_state := presentation.runtime_observation
	return {
		"explorationInput": application.accepts_exploration_input(),
		"routeInput": application.accepts_route_input(),
		"combatPlayback": presentation.is_combat_playback_active(),
		"hostInteraction": lifecycle.has_active_interaction(),
		"committedRevision": session.view().revision,
		"presentedRevision": presentation_state["presentedRevision"],
		"presentationDrawnRevision": presentation_state["drawnRevision"],
		"deferredRevision": presentation_state["deferredRevision"],
		"playbackPhase": presentation_state["playbackPhase"],
		"autoContinuation": persistent_auto.call("observation"),
	}
