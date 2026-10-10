## Retains the detached opening formation before automatic turns resolve.
class_name BattleStartedEvent
extends DomainEvent

var opening_combat: CombatView
var opening_party: Array[CharacterView] = []


func _init(facts: Dictionary, state: GameState, content: RealmzContent) -> void:
	super(&"battle_started", facts)
	# These read models are deliberately absent from DomainEvent.to_data().
	# Saves, replay events, and RNG retain their existing wire representation.
	opening_combat = CombatView.new(state.combat, state.party.characters(), content, null, null, null, state)
	for character: CharacterState in state.party.characters():
		opening_party.append(CharacterView.new(character, content))
