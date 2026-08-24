extends RealmzTestCase


func run() -> void:
	var rng := RealmzRng.new(1)
	assert_equal(rng.trace_limit(), RealmzRng.DEFAULT_TRACE_LIMIT, "production RNG uses the bounded 4,096-entry diagnostic window by default")
	assert_equal(rng.draw(100, "vector.first"), 52, "QuickDraw seed 1 first Castle-scaled roll matches")
	assert_equal(rng.draw(100, "vector.second"), 47, "QuickDraw seed 1 second Castle-scaled roll matches")
	assert_equal(rng.draw(100, "vector.third"), 65, "QuickDraw seed 1 third Castle-scaled roll matches")
	assert_equal(rng.snapshot().generator_state, 1_622_650_073, "QuickDraw state follows the documented Park-Miller sequence")
	assert_equal(rng.snapshot().draw_count, 3, "draw count is persisted independently of state")
	assert_equal(rng.trace()[2]["raw"], -21_287, "the returned QuickDraw value is the signed low word")

	var saved := rng.snapshot()
	var restored := RealmzRng.new(99)
	assert_true(restored.restore(saved), "valid RNG state restores")
	assert_equal(restored.draw(6, "vector.after_restore"), rng.draw(6, "vector.control"), "restored state continues the exact sequence")

	var scripted := ScriptedRng.new([-32_767, 0, 32_767])
	assert_equal(scripted.draw(100, "scripted.high-negative"), 100, "Castle scaling uses absolute raw output")
	assert_equal(scripted.draw(100, "scripted.zero"), 1, "Castle Rand returns at least one")
	assert_equal(scripted.draw(100, "scripted.high-positive"), 100, "Castle scaling reaches the requested range")

	var signed := ScriptedRng.new([32_767, 32_767, 32_767])
	assert_equal(signed.draw_classic(0, "scripted.zero-range"), 1, "Castle Rand zero still consumes a draw and returns one")
	assert_equal(signed.draw_classic(-100, "scripted.negative-range"), -98, "Castle Rand preserves signed range multiplication and C truncation")
	assert_equal([signed.draw_between_classic(147, 145, "scripted.inverted-range"), RealmzRng.classic_between_bounds(147, 145), signed.snapshot().draw_count], [147, Vector2i(147, 147), 3], "Castle's inverted 147-through-145 random-battle range consumes one signed draw and can select only battle 147")

	var transactional := ScriptedRng.new([0, 32_767])
	transactional.draw(10, "transaction.before")
	var checkpoint := transactional.checkpoint()
	transactional.draw(10, "transaction.speculative")
	assert_true(transactional.rollback(checkpoint), "a failed simulation operation can restore RNG state without erasing prior trace evidence")
	assert_equal([transactional.snapshot().draw_count, transactional.trace().map(func(entry: Dictionary) -> String: return entry["tag"])], [1, ["transaction.before"]], "rollback removes only speculative draws")
	assert_equal(transactional.draw(10, "transaction.replayed"), 10, "ScriptedRng also restores its fixture cursor for deterministic failure tests")

	var bounded := RealmzRng.new(1, 3)
	for index: int in 5:
		bounded.draw(10, "bounded.%d" % index)
	assert_equal(bounded.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["bounded.2", "bounded.3", "bounded.4"], "production traces retain only the configured newest entries")
	var bounded_checkpoint := bounded.checkpoint()
	bounded.draw(10, "bounded.speculative")
	assert_true(bounded.rollback(bounded_checkpoint), "bounded trace rollback restores entries evicted by speculative work")
	assert_equal(bounded.trace().map(func(entry: Dictionary) -> String: return entry["tag"]), ["bounded.2", "bounded.3", "bounded.4"], "rollback restores the complete bounded diagnostic window")
	var untraced := RealmzRng.new(1, 0)
	assert_equal([untraced.draw_between(2, 4, &"untraced.range"), untraced.trace()], [3, []], "disabling diagnostics never changes inclusive gameplay draws")
	assert_equal(ScriptedRng.new([]).trace_limit(), RealmzRng.UNLIMITED_TRACE, "scripted oracle sources explicitly retain unlimited trace evidence")
