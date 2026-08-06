extends RealmzTestCase


func run() -> void:
	var session := GameSession.new()
	var before_start := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(before_start.state, SessionStep.State.FAILED, "an unstarted session rejects intents")
	assert_equal(before_start.error_code, &"session_not_started", "the rejection is explicit")

	var invalid_start := session.start(null, 42)
	assert_equal(invalid_start.state, SessionStep.State.FAILED, "start requires validated typed content")
	assert_equal(invalid_start.error_code, &"invalid_content", "invalid content never partially starts a session")

	var snapshot := session.snapshot()
	assert_equal(snapshot, null, "an unstarted session has no save boundary")
