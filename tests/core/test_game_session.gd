extends RealmzTestCase


func run() -> void:
	var session := GameSession.new()
	var before_start := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(before_start.state, SessionStep.State.FAILED, "an unstarted session rejects intents")
	assert_equal(before_start.error_code, &"session_not_started", "the rejection is explicit")

	var started := session.start(null, 42)
	assert_equal(started.state, SessionStep.State.COMPLETED, "start commits a session boundary")
	assert_equal(session.view().revision, 1, "start advances the view revision")

	var searched := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(searched.state, SessionStep.State.COMPLETED, "a typed intent commits synchronously")
	assert_equal(session.view().revision, 2, "intent commit advances the view revision")
	assert_true(session.snapshot().has("pending_interaction"), "pending interaction belongs to the snapshot aggregate")
