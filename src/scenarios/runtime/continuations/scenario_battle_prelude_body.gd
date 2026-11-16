## Retains a Classic battle instruction while authored text waits for a click before the
## fight: the instruction's own message, or the chosen battle's before-message.
class_name ScenarioBattlePreludeBody
extends ScenarioRuntimeContinuationBody

## The instruction's message is on screen; the battle has not been chosen yet.
const INSTRUCTION: StringName = &"instruction"
## The chosen battle's before-message is on screen.
const BATTLE: StringName = &"battle"
const OPCODES: Array[int] = [2, 48, 56, 107]

var stage: StringName
var message_id: int
var opcode: int
var gosub: bool
var extra_code: Array[int] = []
## The signed Classic battle the instruction selected; zero until `BATTLE`.
var battle_number: int
var context: ScenarioExecutionContext = ScenarioExecutionContext.empty()


func wire_payload() -> Dictionary:
	return {"stage": String(stage), "messageId": message_id, "opcode": opcode, "gosub": gosub, "extraCode": extra_code.duplicate(), "battleNumber": battle_number, "context": ScenarioExecutionContextCodec.encode(context)}
