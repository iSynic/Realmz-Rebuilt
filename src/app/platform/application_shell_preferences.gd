## Binds shell-only presentation choices to their existing persistence boundary.
class_name ApplicationShellPreferences
extends RefCounted


static func bind(shell: GameShell, settings: PresentationSettings, persist: Callable, fonts_changed: Callable) -> void:
	shell.font_choice_changed.connect(func(role: StringName, identity: String) -> void:
		if not PresentationSettings.font_choice_is_valid(identity) or role not in [&"interface", &"narrative"]:
			return
		if role == &"interface":
			settings.interface_font = identity
		else:
			settings.narrative_font = identity
		fonts_changed.call()
	)
	shell.show_overworld_command_titles_changed.connect(func(enabled: bool) -> void:
		settings.show_overworld_command_titles = enabled
		shell.apply_settings(settings)
		persist.call()
	)
	shell.integer_fit_hidden_commands_changed.connect(func(enabled: bool) -> void:
		settings.integer_fit_hidden_commands = enabled
		shell.apply_settings(settings)
		persist.call()
	)
