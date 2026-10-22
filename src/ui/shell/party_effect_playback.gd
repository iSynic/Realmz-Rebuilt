## Retains event-local field health until the matching portrait effect completes.
class_name PartyEffectPlayback
extends RefCounted

var base_view: GameView
var health: Dictionary = {}
var _results: Dictionary = {}
var _shell: GameShell
var _audio: ClassicAudioPresenter
var _settle: Callable


func bind(shell: GameShell, audio: ClassicAudioPresenter, settle: Callable) -> void:
	_shell = shell
	_audio = audio
	_settle = settle
	audio.character_effect_finished.connect(_on_effect_finished)
	audio.sequence_finished.connect(_on_sequence_finished)
	shell.pause_changed.connect(func(active: bool) -> void:
		if active: skip()
	)


func begin(previous: GameView, events: Array[DomainEvent]) -> bool:
	reset()
	if previous == null or not previous.session_started or not events.any(func(event: DomainEvent) -> bool: return event.kind == &"character_effect_requested"):
		return false
	base_view = previous
	for character: CharacterView in previous.party_members:
		health[character.id] = character.current_health
	var unmatched: Array[DomainEvent] = []
	for event: DomainEvent in events:
		match event.kind:
			&"character_effect_requested":
				unmatched.append(event)
			&"scenario_spell_applied":
				_assign_result(unmatched, String(event.payload.get("characterId", "")), int(event.payload["healthAfter"]))
			&"party_health_changed":
				for hit: Dictionary in event.payload.get("hits", []):
					_assign_result(unmatched, String(hit["characterId"]), int(hit["health"]), "classic-opcode-15")
	_hold_roster(true)
	return true


func is_active() -> bool:
	return base_view != null


func complete_effect(event: DomainEvent) -> void:
	if _results.has(event):
		health[String(event.payload.get("characterId", ""))] = _results[event]


func reset() -> void:
	if base_view != null: _hold_roster(false)
	base_view = null
	health.clear()
	_results.clear()


func cancel() -> void:
	if not is_active(): return
	reset()
	_audio.skip_effects()
	_shell.roster.cancel_character_effects()


func skip() -> void:
	if not is_active(): return
	_shell.roster.cancel_character_effects()
	_audio.skip_effects()


func _hold_roster(active: bool) -> void:
	if _shell == null: return
	_shell.commands.party_effect_playback = active
	_shell.hud.set_party_effect_playback(active)


func _on_effect_finished(event: DomainEvent) -> void:
	if not is_active(): return
	_shell.roster.finish_character_effect(String(event.payload.get("characterId", "")))
	complete_effect(event)
	_shell.roster.present_playback_health(health)


func _on_sequence_finished() -> void:
	if not is_active(): return
	reset()
	_settle.call()


func _assign_result(unmatched: Array[DomainEvent], character_id: String, value: int, source: String = "") -> void:
	# Opcode 15/16 publishes its hit list after all recipient effects; opcode
	# 18/19 publishes each result immediately after its own effect.
	for index: int in range(unmatched.size() - 1, -1, -1):
		var effect := unmatched[index]
		if String(effect.payload.get("characterId", "")) == character_id and (source.is_empty() or String(effect.payload.get("source", "")) == source):
			_results[effect] = value
			unmatched.remove_at(index)
			return
