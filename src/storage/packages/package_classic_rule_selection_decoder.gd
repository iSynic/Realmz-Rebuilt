## Decodes the explicit compiler choice and complete effective rule commitments.
class_name PackageClassicRuleSelectionDecoder
extends PackageDecoderBase


func decode(value: Variant) -> ClassicRecordCatalog.RuleSelection:
	clear_error()
	if value == null: return null
	var fields: Array[String] = ["nativeMenuSelection", "capturedSourceSetSha256", "raceSource", "casteSource", "projectedRules"]
	if not value is Dictionary or not _exact_fields(value, fields) or not _is_integer(value.nativeMenuSelection) or _integer(value.nativeMenuSelection) not in range(1, 32768) or not _is_sha256(value.capturedSourceSetSha256) or value.raceSource not in ["scenario", "application"] or value.casteSource not in ["scenario", "application"]:
		_reject("Classic rule selection has invalid fields or source choices.")
		return null
	if not value.projectedRules is Dictionary or not _exact_fields(value.projectedRules, ["races", "castes"]):
		_reject("Classic projected rule families are invalid.")
		return null
	var result := ClassicRecordCatalog.RuleSelection.new()
	result.native_menu_selection = _integer(value.nativeMenuSelection)
	result.captured_source_set_sha256 = value.capturedSourceSetSha256
	result.race_source = StringName(value.raceSource)
	result.caste_source = StringName(value.casteSource)
	for family: String in ["races", "castes"]:
		var rows: Variant = value.projectedRules[family]
		if not rows is Array or rows.size() != 30:
			_reject("Classic projected rules must retain thirty fixed logical slots per family.")
			return null
		var seen: Dictionary = {}
		for row: Variant in rows:
			var expected_id := "classic.%s.%d" % ["race" if family == "races" else "caste", seen.size() + 1]
			if not row is Dictionary or not _exact_fields(row, ["id", "sha256"]) or not row.id is String or row.id != expected_id or row.sha256 != null and not _is_sha256(row.sha256) or seen.has(row.id):
				_reject("Classic projected rule identity or digest is invalid.")
				return null
			seen[row.id] = true
			var digest := ClassicRecordCatalog.ProjectionDigest.new(row.sha256) if row.sha256 != null else null
			result.projected_rules.append(ClassicRecordCatalog.RuleProjection.new(StringName(family), row.id, digest))
		for native_id: int in range(1, 31):
			if not seen.has("classic.%s.%d" % ["race" if family == "races" else "caste", native_id]):
				_reject("Classic projected rules changed a fixed logical identity.")
				return null
	return result
