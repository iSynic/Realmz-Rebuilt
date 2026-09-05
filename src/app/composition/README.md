# Application composition

`realmz_application.gd` is the composition root: it creates concrete startup, session, platform, shell, and presentation collaborators and connects their public signals. It is the right place to answer “what owns this dependency?” but not the place to add Realmz rules or a forwarding facade.

`application_spatial_layout.gd` maps the authored shell stage onto retained algorithmic map, battlefield, dungeon, and interaction presenters. `application_step_status_text.gd` owns only short host wording. Stable controls remain in `.tscn` scenes, while this folder coordinates existing instances. Composition-sensitive checks are `tests/presentation/test_classic_ui_system.gd`, `tests/presentation/test_classic_ui_shell.gd`, and `tools/runtime_performance_probe.gd`.
