## Implements deterministic combat spell event builder rules without presentation dependencies.

class_name CombatSpellEventBuilder
extends RefCounted

## Builds the presentation-facing domain events emitted by resolved combat spells.


static func append_sound(events: Array[DomainEvent], authored_sound_id: int, source: String) -> void:
	var native_sound_id := authored_sound_id + 600
	if native_sound_id == 0:
		return
	events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": source}))


static func append_cast(events: Array[DomainEvent], actor_id: String, spell: SpellDefinition, resolutions: GroupSpellResolution, center: Vector2i, shape: int, source: String) -> void:
	var target_id := resolutions.target_ids[0] if not resolutions.target_ids.is_empty() else ""
	var payload := {"actorId": actor_id, "targetId": target_id, "spellId": spell.id, "spellName": spell.name, "classicEffectResourceId": 11_992 + spell.look_start * 8, "source": source}
	if shape > 0:
		payload["areaCenter"] = [center.x, center.y]
		payload["areaShape"] = shape
	events.append(DomainEvent.new(&"combat_spell_cast", payload))


static func append_projectile(events: Array[DomainEvent], actor_id: String, target_id: String, spell: SpellDefinition, source: String) -> void:
	if not spell.target_type in [0, 1, 2, 5, 6, 7, 8, 11]:
		return
	events.append(DomainEvent.new(&"combat_spell_projectile", {"actorId": actor_id, "targetId": target_id, "spellId": spell.id, "classicBattleTileId": 200 + spell.look_start, "source": source}))


static func append_resolution_effect(payload: Dictionary, spell: SpellDefinition, sequence_index: int, sequence_count: int, target_defeated: bool) -> void:
	payload["spellName"] = spell.name
	payload["castSequenceIndex"] = sequence_index
	payload["castSequenceCount"] = sequence_count
	# Castle bypasses the ordinary eight-frame resolution effect when the target
	# dies, while group-body flashes (target types 9 and 10) use a separate path.
	if target_defeated or spell.target_type in [9, 10]:
		return
	var first_resource_id := 12_032 if spell.look_end == 0 else 11_992 + spell.look_end * 8
	var effect_ids: Array[int] = []
	for frame_offset: int in 8:
		effect_ids.append(first_resource_id + frame_offset)
	payload["classicResolutionEffectResourceIds"] = effect_ids
