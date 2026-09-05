# Application startup

Begin here when changing the launch card, campaign discovery, package preparation, or the handoff into the loaded application.

`StartupFrontDoor` draws the minimal first frame and requests the application scene in the background. `PackageHostController` discovers packages and performs cancellable validation/preparation. It returns detached `CampaignPackageView`, `PackageOperationView`, and `PreparedPackage` values; `StartupRouteBridge` then hands the ready application to its normal routes.

The important invariant is transactional startup: failed or cancelled work cannot replace the current session or media catalog. Preparation must remain off the interactive frame, and every retained worker must be joined during shutdown. The owning checks are `tests/presentation/test_classic_ui_system.gd`, package repository tests, and `tools/startup_probe.gd`.
