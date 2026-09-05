## Creates field-spell and scroll session continuations.

class_name MagicContinuations
extends RefCounted


static func field_spell_target(body: TargetingContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"field-spell-target-selection", body)


static func scroll_target(body: TargetingContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"scroll-target-selection", body)


static func scroll_discard(body: TargetingContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"scroll-discard-confirmation", body)
