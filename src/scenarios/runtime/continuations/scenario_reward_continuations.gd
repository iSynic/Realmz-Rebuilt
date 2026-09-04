## Creates reward-owned scenario runtime continuations.

class_name ScenarioRewardContinuations
extends RefCounted


static func reward(state: ClassicRewardState) -> ScenarioRuntimeContinuation:
	var body := ScenarioRewardContinuationBody.new()
	body.state = ClassicRewardState.from_data(state.to_data())
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_REWARD, body)
