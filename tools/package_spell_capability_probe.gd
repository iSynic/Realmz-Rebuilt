extends SceneTree

const PERFORMANCE_PACKAGE_LOADER := preload("res://tools/performance_package_loader.gd")

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/package_spell_capability_probe.gd -- <package.realmz2>")
		call_deferred("_quit_cleanly", 2)
		return
	var loaded := PERFORMANCE_PACKAGE_LOADER.load_scenario(arguments[0])
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	print(CanonicalJson.encode(_capability_report(loaded.content)))
	call_deferred("_quit_cleanly", 0)


func _capability_report(content: RealmzContent) -> Dictionary:
	var role_counts: Dictionary = {}
	var family_counts: Dictionary = {}
	var context_counts: Dictionary = {}
	var scenario_signatures: Dictionary = {}
	for spell: SpellDefinition in content.magic.definitions():
		var role := String(ClassicSpellIdentityCatalog.application_role(spell))
		var family := String(ClassicSpellClassificationRules.mechanical_family(spell))
		var contexts: Dictionary = ClassicSpellDispositionRules.runtime_contexts(spell)
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		family_counts[family] = int(family_counts.get(family, 0)) + 1
		for context_name: String in contexts:
			var disposition := "%s:%s" % [context_name, contexts[context_name]]
			context_counts[disposition] = int(context_counts.get(disposition, 0)) + 1
		if role != String(ClassicSpellIdentityCatalog.ROLE_UNKNOWN):
			continue
		var behavior := ClassicSpellClassificationRules.behavior_signature(spell)
		var signature_id := CanonicalJson.encode(behavior).sha256_text().substr(0, 16)
		var record: Dictionary = scenario_signatures.get(signature_id, {
			"behavior": behavior,
			"count": 0,
			"family": family,
			"runtimeContexts": contexts,
			"signatureId": signature_id,
		})
		record["count"] = int(record["count"]) + 1
		scenario_signatures[signature_id] = record
	var signatures: Array[Dictionary] = []
	var signature_ids: Array = scenario_signatures.keys()
	signature_ids.sort()
	var pending_signatures := 0
	for signature_id: String in signature_ids:
		var record: Dictionary = scenario_signatures[signature_id]
		if record["runtimeContexts"].values().has(String(ClassicSpellDispositionRules.DISPOSITION_PENDING)):
			pending_signatures += 1
		signatures.append(record)
	var monster_spell_references := _monster_spell_references(content)
	return {
		"definitionCount": content.magic.definitions().size(),
		"blockedMonsterSpellReferences": monster_spell_references["blockedReferences"],
		"familyCounts": family_counts,
		"monsterSpellReferenceCount": monster_spell_references["referenceCount"],
		"packageHash": content.package_hash,
		"pendingScenarioSignatureCount": pending_signatures,
		"roleCounts": role_counts,
		"runtimeContextCounts": context_counts,
		"scenarioSignatureCount": signatures.size(),
		"scenarioSignatures": signatures,
	}


func _monster_spell_references(content: RealmzContent) -> Dictionary:
	var reference_count := 0
	var blocked_by_signature: Dictionary = {}
	for monster: MonsterDefinition in content.combat.definitions():
		for spell_id: String in monster.spell_ids():
			if spell_id.is_empty():
				continue
			reference_count += 1
			var spell := content.magic.spell_by_id(spell_id)
			var reason := "missing-spell-definition" if spell == null else CombatMonsterAutomation.monster_spell_unavailable_reason(spell)
			if reason.is_empty():
				continue
			var behavior: Dictionary = {"missingDefinition": true} if spell == null else ClassicSpellClassificationRules.behavior_signature(spell)
			var signature_id := CanonicalJson.encode(behavior).sha256_text().substr(0, 16)
			var record: Dictionary = blocked_by_signature.get(signature_id, {"behavior": behavior, "count": 0, "reason": reason, "signatureId": signature_id})
			record["count"] = int(record["count"]) + 1
			blocked_by_signature[signature_id] = record
	var blocked_references: Array[Dictionary] = []
	var signature_ids: Array = blocked_by_signature.keys()
	signature_ids.sort()
	for signature_id: String in signature_ids:
		blocked_references.append(blocked_by_signature[signature_id])
	return {"blockedReferences": blocked_references, "referenceCount": reference_count}


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
