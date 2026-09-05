# Packages

`PackageRepository` discovers, validates, installs, caches, and releases immutable `.realmz2` packages. It loads the pinned application catalog first, then applies exact-ID scenario overlays before cross-reference validation. `PackageDomainAssembler` constructs a small `RealmzContent` aggregate whose `scenario_records`, `characters`, `items`, `magic`, `combat`, and `economy` catalogs own direct immutable lookup. A scenario package therefore contains only scenario-owned content and legal overrides.

The release-owned campaign archives and their exact provenance catalogs are under `src/storage/packages/bundled_campaigns`. They enter the ordinary package discovery, validation, and immutable installation path rather than bypassing it.

Package dictionaries stop inside storage codecs and validators. Callers receive typed content, media, progress, and errors. `test_package_repository.gd` owns trust and composition; `test_package_install_task.gd` owns worker lifecycle. Use the package probes for timing and never benchmark a scenario without the application catalog.

`src/storage/packages/canonical_json.gd` owns the deterministic dictionary representation used by package hashes and exact repository readback checks. Character and settings repositories reuse that codec; they do not define competing JSON ordering rules.
