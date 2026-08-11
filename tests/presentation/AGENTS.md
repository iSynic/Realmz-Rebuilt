# Purpose

- Own deterministic tests and typed fixtures for presentation-only behavior.

# Ownership

- Responsive profile, route scenes, Classic shell composition, full-stage overlay and spatial-renderer suppression, pointer hit-test ownership, land mouse/keypad diagonals, exact built-in Classic party-marker provenance, unadorned marker presentation, seamless/non-stretched stone surfaces and picture-bevel backing, stable menu-state text metrics, edge-to-edge narrative replacement, inset age-update composition, asset/font provenance, focus/navigation, typed media collision, safe detached display, interaction identity and Classic choice context, fixed maximized-map camera geometry, native actor-centered tactical camera and atlas composition, nonobscuring combat controls, and 2D/3D projection tests.
- `ClassicUiFixtureGallery` supplies nominal, empty, loading, error, unavailable, oversized, missing-media, unidentified, and six-member states for every route and interaction kind, including exact-charge fumbled-item recovery, ordinary treasure, capacity blockers, detection/identification, level results, long spell-selection lists, an eight-direction tactical combat workspace, and host-owned End Adventure choices.
- Inventory presentation coverage keeps character and exact-item selection separate, verifies detached enabled/disabled item actions and trade targets, and rejects an ordinary Store command.
- Shop component coverage includes unaffordable stock, unidentified names, paid identification, equipped-sale rejection, and buyback stock so service regressions remain visible without commercial campaign data.
- `capture_classic_ui_gallery.gd` writes representative local frames under ignored `artifacts/ui-gallery/`; it is visual evidence, not a golden-image test.

# Local Contracts

- Fixture facts are synthetic and cannot become gameplay or live-campaign evidence.
- Local screenshots may prove visual layout only and remain under ignored artifact storage.
- Test navigation must not mutate a session.

# Work Guidance

- Cover 800x600, 960x600, 1280x720, 1600x900, and 1920x1080 plus 100-150 percent text/interface combinations and 1x/2x original art.

# Verification

- Run `godot --headless --path . --script res://tests/test_runner.gd` and `tools/verify.ps1`.
- Party Order presentation fixtures use the real Character route workspace. They prove local move/cancel staging, one typed Apply intent, and visible core-owned disabled reasons without creating test-only gameplay mutation paths.
- Character-sheet fixtures cover disabled/dead and long identity content, named conditions and eight saves, personal wealth, special modifiers and abilities, race/caste metadata, all five age bands, mutation-free `FD-CHARACTER-004` highlighting, and an explicit unavailable lifetime record. Tab and inspected-character selection remain presentation-only.
- Party-setup inspection fixtures cover assembled members plus eligible and ineligible vault revisions, exact eligibility reasons, the shared complete sheet, and mutation-free Back navigation.
- Inventory workspace fixtures cover identified and unidentified fact visibility, Castle's concealed/revealed curse decoy, source-backed detail fields, and inline disabled-action reasons.
- System workspace fixtures cover detached current and backup save facts, distinct load operations, and disabled corrupt-record reasons without reading host files.
- Lifecycle fixtures distinguish End Adventure from process Quit, cover each field/combat/no-session option set, and prove save-failure suppression, explicit no-save, Cancel, and response identity without closing the test process or treating the host prompt as gameplay state.
- Package-library fixtures distinguish manifest availability from full readiness and cover determinate worker progress, competing-action suppression, Cancel signaling, and terminal cleanup without opening archives from presentation.
- Appearance fixtures cover both exact package roles, recommendation-first browsing, presentation-only preview, one typed Apply request, no-op Discard, long labels, and visible core-owned unavailable reasons.
- Use MCP after `play_scene` to confirm mouse activation for campaign selection, AP Continue responses, and original-bitmap encounter actions; keyboard activation alone is insufficient pointer evidence.

# Child DOX Index
