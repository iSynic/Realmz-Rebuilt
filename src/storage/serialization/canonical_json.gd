class_name CanonicalJson
extends RefCounted


static func encode(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return JSON.stringify(value)
		TYPE_FLOAT:
			if is_equal_approx(value, round(value)):
				return str(int(value))
			return JSON.stringify(value)
		TYPE_ARRAY:
			var items: Array[String] = []
			for item: Variant in value:
				items.append(encode(item))
			return "[" + ",".join(items) + "]"
		TYPE_DICTIONARY:
			var keys: Array[String] = []
			for key: Variant in value.keys():
				keys.append(String(key))
			keys.sort()
			var members: Array[String] = []
			for key: String in keys:
				members.append(JSON.stringify(key) + ":" + encode(value[key]))
			return "{" + ",".join(members) + "}"
		_:
			push_error("Canonical JSON cannot encode Variant type %s." % type_string(typeof(value)))
			return "null"
