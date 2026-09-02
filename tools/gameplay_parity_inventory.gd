extends SceneTree

const APPLICATION_PACKAGE_PATH := "res://src/infrastructure/characters/realmz-classic-character-library.realmz2"
const APPLICATION_PACKAGE_ID := "realmz-classic-character-library"
const APPLICATION_PACKAGE_HASH := "6e3f23c9a452f70b25040c729e17533de5ddf0c420ff35484fc52f6e0dd25e68"
const FEATURE_REPORT_FORMAT_VERSION := 2
const FEATURE_REPORT_PROVIDENCE_COMMIT := "8ae731e851544575d6687059b9c84a2535f89d5f"
const FEATURE_REPORT_SCHEMA_HASH := "be4fa175ebfc8ed756a0db2b0c6073108bd9f635e8c23321d1258cfcf4e73ee4"
const INVENTORY_PATH := "res://tests/fixtures/oracle/classic-gameplay-parity-inventory.json"
const REPORT_PATH := "res://docs/classic-gameplay-parity-status.md"
const SpellCapabilities = preload("res://src/core/rules/classic_spell_capability_catalog.gd")

var _write := false


func _initialize() -> void:
	_write = "--write" in OS.get_cmdline_user_args()
	var repository := PackageRepository.new()
	var loaded := repository.load_bundled_package(APPLICATION_PACKAGE_PATH, APPLICATION_PACKAGE_ID, APPLICATION_PACKAGE_HASH)
	if not loaded.is_ok():
		_fail("Application package load failed: %s" % loaded.error_message)
		repository.close()
		return
	var inventory := _build_inventory(loaded.content)
	var inventory_errors := _inventory_errors(inventory)
	if not inventory_errors.is_empty():
		_fail("Parity inventory invariant failed: %s" % "; ".join(inventory_errors))
		repository.close()
		return
	var inventory_text := CanonicalJson.encode(inventory) + "\n"
	var report_text := _build_report(inventory)
	var ok := _write_or_check(INVENTORY_PATH, inventory_text)
	ok = _write_or_check(REPORT_PATH, report_text) and ok
	repository.close()
	if ok:
		print("Gameplay parity inventory %s." % ["written" if _write else "verified"])
		quit(0)


func _build_inventory(content: RealmzContent) -> Dictionary:
	var opcodes: Array[Dictionary] = []
	var opcode_counts := {"executable": 0, "classic-reserved": 0, "unsupported-pending": 0}
	for opcode: int in ClassicOpcodeCatalog.classic_opcode_identities():
		var disposition := String(ClassicOpcodeCatalog.disposition(opcode))
		opcode_counts[disposition] = int(opcode_counts.get(disposition, 0)) + 1
		opcodes.append({
			"disposition": disposition,
			"evidence": _opcode_evidence(disposition, ClassicOpcodeCatalog.evidence_reference(opcode)),
			"evidenceReference": ClassicOpcodeCatalog.evidence_reference(opcode),
			"normalizedOpcode": ClassicOpcodeCatalog.normalize(opcode),
			"opcode": opcode,
			"owner": String(ClassicOpcodeCatalog.owner(opcode)),
		})

	var spells: Array[Dictionary] = []
	var signature_groups: Dictionary = {}
	var role_counts := {
		String(SpellCapabilities.ROLE_APPLICATION_EFFECT): 0,
		String(SpellCapabilities.ROLE_RESERVED_STANDARD): 0,
		String(SpellCapabilities.ROLE_STOCK_PLAYER): 0,
		String(SpellCapabilities.ROLE_UNKNOWN): 0,
	}
	var family_counts: Dictionary = {}
	var context_counts: Dictionary = {}
	for spell: SpellDefinition in content.spell_definitions():
		var role := String(SpellCapabilities.application_role(spell))
		var behavior_signature: Dictionary = SpellCapabilities.behavior_signature(spell)
		var mechanical_family := String(SpellCapabilities.mechanical_family(spell))
		var runtime_contexts: Dictionary = SpellCapabilities.runtime_contexts(spell)
		var signature_id := CanonicalJson.encode(behavior_signature).sha256_text().substr(0, 16)
		role_counts[role] = int(role_counts.get(role, 0)) + 1
		family_counts[mechanical_family] = int(family_counts.get(mechanical_family, 0)) + 1
		for context_name: String in runtime_contexts:
			var context_disposition := "%s:%s" % [context_name, runtime_contexts[context_name]]
			context_counts[context_disposition] = int(context_counts.get(context_disposition, 0)) + 1
		var group: Array = signature_groups.get(signature_id, [])
		group.append(spell.classic_id)
		signature_groups[signature_id] = group
		spells.append({
			"behaviorSignature": behavior_signature,
			"classicId": spell.classic_id,
			"evidence": _spell_evidence(role),
			"id": spell.id,
			"mechanicalFamily": mechanical_family,
			"name": spell.name,
			"packedFamily": SpellCapabilities.packed_family(spell),
			"packedLevel": SpellCapabilities.packed_level(spell),
			"packedSlot": SpellCapabilities.packed_slot(spell),
			"presentationSignature": {
				"lookEnd": spell.look_end,
				"lookStart": spell.look_start,
				"queueIcon": spell.queue_icon,
				"soundEnd": spell.sound_end,
				"soundStart": spell.sound_start,
			},
			"role": role,
			"runtimeContexts": runtime_contexts,
			"signatureId": signature_id,
		})
	var signatures: Array[Dictionary] = []
	var signature_ids: Array = signature_groups.keys()
	signature_ids.sort()
	for signature_id: String in signature_ids:
		var classic_ids: Array = signature_groups[signature_id]
		classic_ids.sort()
		signatures.append({"classicIds": classic_ids, "count": classic_ids.size(), "signatureId": signature_id})

	var opcode_summary := ClassicOpcodeCatalog.parity_summary()
	return {
		"applicationPackage": {"campaignId": APPLICATION_PACKAGE_ID, "packageHash": APPLICATION_PACKAGE_HASH},
		"corpusSpells": [],
		"evidenceAxes": ["discovered", "compilerPreserved", "runtimeTested", "routeProven", "ordinaryPlayCertified"],
		"featureReportContract": {
			"analyzer": "tools/analyze_gameplay_feature_reports.ps1",
			"formatVersion": FEATURE_REPORT_FORMAT_VERSION,
			"providenceCommit": FEATURE_REPORT_PROVIDENCE_COMMIT,
			"schemaHash": FEATURE_REPORT_SCHEMA_HASH,
		},
		"formatVersion": 2,
		"opcodeSummary": {
			"classicReserved": opcode_counts["classic-reserved"],
			"executable": opcode_counts["executable"],
			"missingEvidence": opcode_summary["missingEvidence"],
			"pending": opcode_counts["unsupported-pending"],
			"total": opcodes.size(),
			"unowned": opcode_summary["unowned"],
			"unknown": opcode_summary["unknown"],
		},
		"opcodes": opcodes,
		"policy": {
			"commercialCorpus": "local-untracked-sidecars-only",
			"runtimeTestedMeaning": "semantic public-boundary behavior proof, not package decoding or handler presence",
			"signatureMeaning": "mechanical fields only; presentation art and sound remain separately inventoried",
		},
		"spellSummary": {
			"applicationEffects": role_counts[String(SpellCapabilities.ROLE_APPLICATION_EFFECT)],
			"behaviorSignatures": signatures.size(),
			"reservedStandardSlots": role_counts[String(SpellCapabilities.ROLE_RESERVED_STANDARD)],
			"stockPlayer": role_counts[String(SpellCapabilities.ROLE_STOCK_PLAYER)],
			"totalDefinitions": spells.size(),
			"unknown": role_counts[String(SpellCapabilities.ROLE_UNKNOWN)],
			"mechanicalFamilies": family_counts,
			"runtimeContexts": context_counts,
		},
		"spells": spells,
		"spellSignatures": signatures,
	}


func _inventory_errors(inventory: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var opcode_summary: Dictionary = inventory["opcodeSummary"]
	var spell_summary: Dictionary = inventory["spellSummary"]
	if opcode_summary != ClassicOpcodeCatalog.parity_summary():
		errors.append("opcode summary does not match the complete catalog audit")
	if spell_summary["totalDefinitions"] != 420 or spell_summary["stockPlayer"] != 252 or spell_summary["applicationEffects"] != 105 or spell_summary["reservedStandardSlots"] != 63:
		errors.append("application spell roles do not match the pinned package denominator")
	if spell_summary["unknown"] != 0:
		errors.append("application spell catalog contains unowned definitions")
	if spell_summary["behaviorSignatures"] <= 0 or spell_summary["behaviorSignatures"] > spell_summary["totalDefinitions"]:
		errors.append("application spell behavior signatures are malformed")
	var family_total := 0
	for count: int in spell_summary["mechanicalFamilies"].values():
		family_total += count
	if family_total != spell_summary["totalDefinitions"]:
		errors.append("application spell capability-family counts are inconsistent")
	for context_name: String in ["combatCharacter", "combatItem", "combatMonster", "combatScroll", "characterProjectile", "fieldCharacter", "monsterProjectile"]:
		var context_total := 0
		for disposition: String in ["executable", "unsupported-pending", "not-applicable"]:
			context_total += int(spell_summary["runtimeContexts"].get("%s:%s" % [context_name, disposition], 0))
		if context_total != spell_summary["totalDefinitions"]:
			errors.append("application spell %s capability counts are inconsistent" % context_name)
	var feature_report_contract: Dictionary = inventory["featureReportContract"]
	if feature_report_contract["formatVersion"] != FEATURE_REPORT_FORMAT_VERSION or feature_report_contract["providenceCommit"] != FEATURE_REPORT_PROVIDENCE_COMMIT or feature_report_contract["schemaHash"] != FEATURE_REPORT_SCHEMA_HASH:
		errors.append("Providence feature-report contract metadata is stale")
	return errors


func _opcode_evidence(disposition: String, reference: String) -> Dictionary:
	var runtime_status := "missing" if disposition == "unsupported-pending" else "not-applicable" if disposition == "classic-reserved" else "partial"
	return {
		"compilerPreserved": {"evidence": "", "status": "not-assessed"},
		"discovered": {"evidence": reference, "status": "verified"},
		"ordinaryPlayCertified": {"evidence": "", "status": "not-assessed"},
		"routeProven": {"evidence": "", "status": "not-assessed"},
		"runtimeTested": {"evidence": reference if disposition == "executable" else "", "status": runtime_status},
	}


func _spell_evidence(role: String) -> Dictionary:
	var reserved := role == String(SpellCapabilities.ROLE_RESERVED_STANDARD)
	return {
		"compilerPreserved": {"evidence": "pinned-application-package", "status": "verified"},
		"discovered": {"evidence": "pinned-application-package", "status": "verified"},
		"ordinaryPlayCertified": {"evidence": "", "status": "not-applicable" if reserved else "not-assessed"},
		"routeProven": {"evidence": "", "status": "not-applicable" if reserved else "not-assessed"},
		"runtimeTested": {"evidence": "", "status": "not-applicable" if reserved else "not-assessed"},
	}


func _build_report(inventory: Dictionary) -> String:
	var opcode_summary: Dictionary = inventory["opcodeSummary"]
	var spell_summary: Dictionary = inventory["spellSummary"]
	var pending: Array[String] = []
	for entry: Dictionary in inventory["opcodes"]:
		if entry["disposition"] == "unsupported-pending":
			pending.append(str(entry["opcode"]))
	return """# Classic gameplay parity status

Generated from `ClassicOpcodeCatalog` and the pinned application package. Do not edit by hand.

## Opcode denominator

- Total identities: %d (`0-127`, `-14`, and `-23`)
- Executable: %d
- Source-reserved: %d
- Behavior-bearing pending: %d
- Pending identities: %s

An executable disposition proves an owned handler boundary, not complete branch, route, or ordinary-play certification. Pending identities remain rejected by package readiness; none are silent no-ops.

## Application spell denominator

- Player spellbook records: %d
- Application effect records: %d
- Reserved standard slots: %d
- Total definitions: %d
- Unique mechanical behavior signatures: %d
- Mechanical families: %s
- Character combat: %d executable, %d pending
- Scroll combat: %d executable, %d pending
- Item combat: %d executable, %d pending
- Monster combat: %d executable, %d pending
- Character projectiles: %d executable, %d pending
- Monster projectiles: %d executable, %d pending
- Character field/camp: %d executable, %d pending

The 252 player records are the stock player-spell parity target. The 105 application effect records cover application-owned monster, item, projectile, and special effects and require their own legal-context proof. The 63 reserved records are denominator entries, not missing player spells. Scenario-corpus custom spells are collected only in local untracked sidecars until their normalized signatures can be committed without commercial content.

## Providence feature reports

- Report format: `realmz2.feature-report` version %d
- Authoritative Providence commit: `%s`
- Mirrored schema SHA-256: `%s`
- Local analyzer and coverage ranking: `tools/analyze_gameplay_feature_reports.ps1`

The sidecar binds its exact package hash and reports normalized feature signatures without scenario names, text, coordinates, record identities, or machine-local paths. Commercial reports remain local and untracked. Coverage ranking is recomputed against already certified reports after each scenario rather than establishing a fixed campaign order.

## Evidence policy

Every entry tracks discovery, compiler preservation, semantic public-runtime testing, deterministic route proof, and ordinary-play certification independently. Package decoding and handler registration never count as semantic spell or opcode parity.
""" % [
		opcode_summary["total"], opcode_summary["executable"], opcode_summary["classicReserved"], opcode_summary["pending"], "None" if pending.is_empty() else ", ".join(pending),
		spell_summary["stockPlayer"], spell_summary["applicationEffects"], spell_summary["reservedStandardSlots"], spell_summary["totalDefinitions"], spell_summary["behaviorSignatures"],
		_format_counts(spell_summary["mechanicalFamilies"]),
		_context_count(spell_summary, "combatCharacter", "executable"), _context_count(spell_summary, "combatCharacter", "unsupported-pending"),
		_context_count(spell_summary, "combatScroll", "executable"), _context_count(spell_summary, "combatScroll", "unsupported-pending"),
		_context_count(spell_summary, "combatItem", "executable"), _context_count(spell_summary, "combatItem", "unsupported-pending"),
		_context_count(spell_summary, "combatMonster", "executable"), _context_count(spell_summary, "combatMonster", "unsupported-pending"),
		_context_count(spell_summary, "characterProjectile", "executable"), _context_count(spell_summary, "characterProjectile", "unsupported-pending"),
		_context_count(spell_summary, "monsterProjectile", "executable"), _context_count(spell_summary, "monsterProjectile", "unsupported-pending"),
		_context_count(spell_summary, "fieldCharacter", "executable"), _context_count(spell_summary, "fieldCharacter", "unsupported-pending"),
		FEATURE_REPORT_FORMAT_VERSION, FEATURE_REPORT_PROVIDENCE_COMMIT, FEATURE_REPORT_SCHEMA_HASH,
	]


static func _context_count(spell_summary: Dictionary, context_name: String, disposition: String) -> int:
	return int(spell_summary["runtimeContexts"].get("%s:%s" % [context_name, disposition], 0))


static func _format_counts(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var values: Array[String] = []
	for key: String in keys:
		values.append("%s=%d" % [key, counts[key]])
	return ", ".join(values)


func _write_or_check(path: String, expected: String) -> bool:
	if _write:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail("Could not write %s" % path)
			return false
		file.store_string(expected)
		file.close()
		return true
	if not FileAccess.file_exists(path):
		_fail("Missing generated parity artifact: %s" % path)
		return false
	if FileAccess.get_file_as_string(path) != expected:
		_fail("Stale generated parity artifact: %s (run tools/verify_gameplay_parity_inventory.ps1 -Write)" % path)
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
