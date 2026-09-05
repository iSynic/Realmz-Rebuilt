## Binds one location service record and exposes its variable action host.
class_name LocationServiceRow
extends HBoxContainer


func bind(title: String) -> void:
	($Title as Label).text = title


func action_host() -> HBoxContainer:
	return $Actions as HBoxContainer
