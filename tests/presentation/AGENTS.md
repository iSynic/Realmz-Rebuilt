# Purpose

- Own deterministic tests and typed fixtures for presentation-only behavior.

# Ownership

- Responsive profile, route scenes, Classic shell composition, full-stage overlay and spatial-renderer suppression, pointer hit-test ownership, land mouse/keypad diagonals, exact built-in Classic party-marker provenance, unadorned marker presentation, seamless/non-stretched stone surfaces and picture-bevel backing, stable menu-state text metrics, edge-to-edge narrative replacement, inset age-update composition, asset/font provenance, focus/navigation, exact scenario-before-application media resolution, safe detached display, interaction identity and Classic choice context, fixed maximized-map camera geometry, native tactical turn-centering plus edge-triggered movement recentering, stable action-actor focus across actorless playback frames, atlas composition, battlefield-owned actor/sequence/area targeting with progressive setup/confirmation visibility, ordered combat playback, synchronous-audio visual blocking, fixed combat command slots with icon-backed current/upcoming initiative inside the default combat region, 960x600 reachability for expanded combat controls, and 2D/3D projection tests.
- `ClassicUiFixtureGallery` supplies nominal, empty, loading, error, unavailable, oversized, missing-media, unidentified, and six-member states for every route and interaction kind, including full-stage genuine ally selection, exact-charge fumbled-item recovery, ordinary treasure, capacity blockers, detection/identification, a populated six-shopper stock/pack workspace, level results, long spell-selection lists, spatial eight-direction combat input with an on-demand cost overlay, and host-owned End Adventure choices. The runtime never emits the empty ally-selection fixture during normal battle return.
- Inventory presentation coverage keeps character and exact-item selection separate, verifies detached enabled/disabled item actions and trade targets, and rejects an ordinary Store command.
- Allies coverage owns the populated and empty read-only workspace invariant, including separate list/detail panes and detached current-state facts. Bestiary coverage is deferred until the package catalog contract is corrected; tests must not fabricate discovery semantics.
- Shop component coverage includes unaffordable stock, unidentified names, paid identification, equipped-sale rejection, and buyback stock so service regressions remain visible without commercial campaign data.
- `capture_classic_ui_gallery.gd` writes representative local frames under ignored `artifacts/ui-gallery/`, including Treasure and Shop at the default 960x600 window; it is visual evidence, not a golden-image test.

# Local Contracts

- Fixture facts are synthetic and cannot become gameplay or live-campaign evidence.
- Local screenshots may prove visual layout only and remain under ignored artifact storage.
- Test navigation must not mutate a session. Automatic-route coverage proves that combat, services, and scenario/AP interactions replace unrelated browsing workspaces while interaction-free browsing remains presentation-owned. Pending mandatory responses disable manual route changes, and full-stage interaction fixtures assert an opaque, pointer-owning layer above nested router overlays.

# Work Guidance

- Cover 800x600, 960x600, 1280x720, 1600x900, and 1920x1080 plus 100-150 percent text/interface combinations and 1x/2x original art.

# Verification

- Run `godot --headless --path . --script res://tests/test_runner.gd` and `tools/verify.ps1`.
- Party Order presentation fixtures use the real Character route workspace. They prove local move/cancel staging, one typed Apply intent, and visible core-owned disabled reasons without creating test-only gameplay mutation paths.
- Character-sheet fixtures cover disabled/dead and long identity content, named conditions and eight saves, personal wealth, special modifiers and abilities, race/caste metadata, all five age bands, mutation-free `FD-CHARACTER-004` highlighting, and an explicit unavailable lifetime record. Tab and inspected-character selection remain presentation-only.
- Party-setup inspection fixtures cover assembled members plus eligible and ineligible vault revisions, exact eligibility reasons, visible core-owned import failures while the shell status region is suppressed, the shared complete sheet, and mutation-free Back navigation.
- Party-setup route fixtures prove that Begin Adventure dismisses a setup-opened Vault, clears its setup-only return history, and enables Exploration without changing ordinary active-session route ownership.
- Inventory workspace fixtures cover identified and unidentified fact visibility, Castle's concealed/revealed curse decoy, source-backed detail fields, and inline disabled-action reasons. The public inventory-session proof owns Cast Identify's party-order caster, fixed cost, all-carried-item mutation, event order, and restore behavior instead of duplicating those rules in UI tests.
- System workspace fixtures cover detached current and backup save facts, distinct load operations, and disabled corrupt-record reasons without reading host files.
- Lifecycle fixtures distinguish End Adventure from process Quit, cover each field/combat/no-session option set, and prove save-failure suppression, explicit no-save, Cancel, and response identity without closing the test process or treating the host prompt as gameplay state.
- Package-library fixtures distinguish manifest availability from full readiness and cover determinate worker progress, competing-action suppression, Cancel signaling, and terminal cleanup without opening archives from presentation.
- Startup-shell fixtures cover the pre-session splash, one aligned and separately backed Scenarios/Character Files/Current Party row, the narrower Scenarios share, six pre-session empty slots, installation rather than Play behavior, absence of ordinary seed controls, full-stage Character Files entry without the persistent roster, and public return navigation. Helper wording remains gallery/manual acceptance under the regression-admission policy. Party-setup fixtures assert that the same three-pane workspace survives selected-package startup, keeps all six occupied party rows visible at 960x600, and leaves advanced revision/archive controls out of ordinary assembly. Surface fixtures require shared root slate through pre-session/setup overlays and opaque bevel corners; menu-state fixtures cover no-session and party-setup route suppression, disabled parent menus, and opaque popup borders.
- Appearance fixtures cover both exact package roles, recommendation-first browsing, presentation-only preview, one typed Apply request, no-op Discard, long labels, and visible core-owned unavailable reasons.
- Use MCP after `play_scene` to confirm mouse activation for campaign selection, AP Continue responses, and original-bitmap encounter actions; keyboard activation alone is insufficient pointer evidence.

# Child DOX Index
