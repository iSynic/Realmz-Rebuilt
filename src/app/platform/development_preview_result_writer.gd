## Writes the strict Providence preview result without retaining runtime state.

class_name DevelopmentPreviewResultWriter
extends RefCounted

const KIND := "realmz2.preview-result"
const FORMAT_VERSION := 1


static func write(request: DevelopmentPreviewRequest, fields: Dictionary) -> String:
	if request == null:
		return "The preview request is unavailable."
	var result := {"kind": KIND, "formatVersion": FORMAT_VERSION}
	result.merge(fields, true)
	var file := FileAccess.open(request.result_path, FileAccess.WRITE)
	if file == null:
		return "The preview result could not be written."
	file.store_string(CanonicalJson.encode(result) + "\n")
	file.close()
	print("PREVIEW_%s %s" % [String(result["status"]).to_upper(), CanonicalJson.encode(result)])
	return ""
