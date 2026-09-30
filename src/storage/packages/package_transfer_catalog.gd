## Records normalized full definitions without changing package or save schemas.
class_name PackageTransferCatalog
extends RefCounted


static func build(content: Dictionary, application: RealmzContent) -> ContentTransferCatalog:
	var result := ContentTransferCatalog.new()
	if application != null:
		result.inherit_application(application.transfer_catalog)
	for family: String in ["races", "castes", "items", "spells"]:
		for raw: Dictionary in content.get(family, []):
			var normalized := raw.duplicate(true)
			if family in ["races", "castes"]:
				normalized.erase("name")
				normalized.erase("description")
			if family == "items":
				if normalized.has("raceRestrictions"):
					normalized["raceRestrictions"] = int(normalized["raceRestrictions"]) & 0xFF80
				if normalized.has("casteRestrictions"):
					normalized["casteRestrictions"] = int(normalized["casteRestrictions"]) & 0xFE00
			result.record(StringName(family), String(raw["id"]), CanonicalJson.encode(normalized).sha256_text(), application != null)
	return result
