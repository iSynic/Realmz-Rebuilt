## Prevents stock fallback from concealing a missing scenario rule override.
class_name PackageClassicRuleSelectionBinding
extends RefCounted


static func bind(content: RealmzContent, records: ClassicRecordCatalog) -> String:
	for spell: SpellDefinition in content.magic.definitions():
		var id := spell.classic_id
		if int(id / 1000) not in range(1, 6) or int(id % 1000 / 100) not in range(1, 8) or id % 100 not in range(1, 16):
			return "Compiled spell %d is outside the five native seven-by-fifteen spell banks." % id
	var owned_error := _bind_owned_records(content.transfer_catalog, records)
	if not owned_error.is_empty(): return owned_error
	for family: StringName in [&"races", &"castes"]:
		if not family_is_native(records, family): continue
		var path := "Data Race" if family == &"races" else "Data Caste"
		var source := records.source_by_path(path)
		var count := 0 if source == null else mini(30, int(source.effective_byte_length / (408 if family == &"races" else 576)))
		var definitions: Array = content.characters.race_definitions() if family == &"races" else content.characters.caste_definitions()
		if definitions.size() != count: return "A native rule family differs from its supplied complete prefix."
		for definition: Variant in definitions:
			if definition.classic_id < 1 or definition.classic_id > count:
				return "A native rule definition has no complete source row."
	if records.rule_selection != null:
		var selection := records.rule_selection
		for field: Array in [["Data Race", selection.race_source], ["Data Caste", selection.caste_source]]:
			var expected := &"scenario" if selection.native_menu_selection >= 20 and records.source_by_path(field[0]) != null else &"application"
			if field[1] != expected: return "Classic rule selection changed its captured family source."
		if selection.captured_source_set_sha256 != source_set_sha256(records):
			return "Classic rule selection is not bound to the captured source inventory."
		for projection: ClassicRecordCatalog.RuleProjection in records.rule_selection.projected_rules:
			var actual := content.transfer_catalog.projection_fingerprint(projection.family, projection.id)
			if rule_is_absent(records, projection.family, projection.id):
				if projection.digest != null or not actual.is_empty(): return "An unavailable native rule has a fabricated effective definition or digest."
				continue
			if projection.digest == null or actual != projection.digest.sha256:
				return "The composed %s rule '%s' differs from its complete compiler projection." % [projection.family, projection.id]
			if family_is_native(records, projection.family) and not content.transfer_catalog.is_scenario_owned(projection.family, projection.id):
				return "A supplied native rule has no package-owned definition."
		return ""
	# Unknown selection cannot authorize application substitution for captured rules.
	for family: String in ["races", "castes"]:
		var source := records.source_by_path("Data Race" if family == "races" else "Data Caste")
		if source == null: continue
		var count := mini(30, int(source.effective_byte_length / (408 if family == "races" else 576)))
		for native_id: int in range(1, count + 1):
			var identity := "classic.%s.%d" % ["race" if family == "races" else "caste", native_id]
			if not content.transfer_catalog.is_scenario_owned(StringName(family), identity):
				return "A captured native rule '%s' has no package-owned definition or explicit rule selection." % identity
	return ""


static func family_is_native(records: ClassicRecordCatalog, family: StringName) -> bool:
	if records == null: return false
	if records.rule_selection != null:
		return (records.rule_selection.race_source if family == &"races" else records.rule_selection.caste_source) == &"scenario"
	return records.source_by_path("Data Race" if family == &"races" else "Data Caste") != null


static func rule_is_absent(records: ClassicRecordCatalog, family: StringName, id: String) -> bool:
	if not family_is_native(records, family): return false
	var prefix := "classic.race." if family == &"races" else "classic.caste."
	var suffix := id.trim_prefix(prefix)
	if not id.begins_with(prefix) or not suffix.is_valid_int() or str(suffix.to_int()) != suffix or suffix.to_int() < 1 or suffix.to_int() > 30: return false
	return records.lookup("Data Race" if family == &"races" else "Data Caste", suffix.to_int() - 1).availability != ClassicRecordCatalog.Availability.COMPLETE


static func _bind_owned_records(catalog: ContentTransferCatalog, records: ClassicRecordCatalog) -> String:
	for family: Array in [["Data NI", &"items", 100, 200], ["Data Spell", &"spells", 30, 105]]:
		var source := records.source_by_path(family[0])
		if source == null: continue
		for native_id: int in mini(family[3], int(source.effective_byte_length / family[2])):
			var identity := "classic.item.%d" % (800 + native_id) if family[1] == &"items" else "classic.spell.%d" % (5101 + (native_id / 15) * 100 + native_id % 15)
			if not catalog.is_scenario_owned(family[1], identity):
				return "The compiler omitted complete native record '%s' #%d." % [family[0], native_id]
	return ""


static func source_set_sha256(records: ClassicRecordCatalog) -> String:
	var sources := records.sources()
	sources.sort_custom(func(left: ClassicRecordCatalog.Source, right: ClassicRecordCatalog.Source) -> bool: return left.native_path < right.native_path)
	var rows: Array[Dictionary] = []
	for source: ClassicRecordCatalog.Source in sources:
		# Match the pinned serde struct order; this provenance digest is not canonical row JSON.
		rows.append({"nativePath": source.native_path, "blob": "sha256:" + source.sha256, "byteLength": source.byte_length})
	return JSON.stringify(["providence-classic-source-set-v1", rows], "", false, true).sha256_text()
