## Records normalized full definitions without changing package or save schemas.
class_name PackageTransferCatalog
extends RefCounted


static func build(content: Dictionary, application: RealmzContent, native_records: ClassicRecordCatalog = null) -> ContentTransferCatalog:
	var result := ContentTransferCatalog.new()
	if application != null:
		result.inherit_application(application.transfer_catalog)
		if native_records != null:
			for item: ItemDefinition in application.items.definitions():
				if item.classic_id >= 800: result.exclude_definition(&"items", item.id)
			for family: StringName in [&"races", &"castes"]:
				if PackageClassicRuleSelectionBinding.family_is_native(native_records, family):
					for native_id: int in range(1, 31):
						result.exclude_definition(family, "classic.%s.%d" % ["race" if family == &"races" else "caste", native_id])
	for family: String in ["races", "castes", "items", "spells"]:
		for raw: Dictionary in content.get(family, []):
			result.record_projection(StringName(family), String(raw["id"]), CanonicalJson.encode(raw).sha256_text())
			var normalized := raw.duplicate(true)
			if family in ["races", "castes"]:
				normalized.erase("name")
				normalized.erase("description")
				# Castle uses these lists for creation, not existing-character admission.
				normalized.erase("eligibleCasteIds" if family == "races" else "eligibleRaceIds")
				normalized.erase("defaultIconSet" if family == "races" else "defaultIcon")
			if family == "items":
				if normalized.has("raceRestrictions"):
					normalized["raceRestrictions"] = int(normalized["raceRestrictions"]) & 0xFF80
				if normalized.has("casteRestrictions"):
					normalized["casteRestrictions"] = int(normalized["casteRestrictions"]) & 0xFE00
			result.record(StringName(family), String(raw["id"]), CanonicalJson.encode(normalized).sha256_text(), application != null)
	return result
