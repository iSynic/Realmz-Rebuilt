extends SceneTree

const SpellCapabilities = preload("res://src/core/rules/classic_spell_capability_catalog.gd")


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		printerr("Usage: godot --headless --path <project> --script res://tools/package_spell_capability_probe.gd -- <package.realmz2>")
		call_deferred("_quit_cleanly", 2)
		return
	var loaded := PackageRepository.new().load_package(arguments[0])
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
	for spell: SpellDefinition in content.spell_definitions():
		var role := String(SpellCapabilities.application_role(spell))
		var family := String(SpellCapabilities.mechanical_family(spell))
		var contexts: Dictionary = SpellCapabilities.runtime_contexts(spell)
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		family_counts[family] = int(family_counts.get(family, 0)) + 1
		for context_name: String in contexts:
			var disposition := "%s:%s" % [context_name, contexts[context_name]]
			context_counts[disposition] = int(context_counts.get(disposition, 0)) + 1
		if role != String(SpellCapabilities.ROLE_UNKNOWN):
			continue
		var behavior := SpellCapabilities.behavior_signature(spell)
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
		if record["runtimeContexts"].values().has(String(SpellCapabilities.DISPOSITION_PENDING)):
			pending_signatures += 1
		signatures.append(record)
	return {
		"definitionCount": content.spell_definitions().size(),
		"familyCounts": family_counts,
		"packageHash": content.package_hash,
		"pendingScenarioSignatureCount": pending_signatures,
		"roleCounts": role_counts,
		"runtimeContextCounts": context_counts,
		"scenarioSignatureCount": signatures.size(),
		"scenarioSignatures": signatures,
	}


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
