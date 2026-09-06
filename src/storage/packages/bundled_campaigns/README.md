# Bundled campaigns

This directory contains the thirteen Castle-distributed campaigns shipped with Realmz Rebuilt. The `.realmz2` archives are immutable Providence outputs containing scenario-owned custom tables, media, and exact overrides; stock definitions and media live once in the application library. `castle-bundled-scenarios.provenance.json` records their source, compiler, ownership inventory, package identity, size, and hashes. City of Bywater additionally uses the owner-designated source recorded in `city-of-bywater.source.json`.

Runtime discovery treats these archives like external packages: first Play performs complete validation and installs the exact bytes into the user's immutable package library. Regenerate them only through the pinned Providence workflow, update the provenance catalogs atomically, and run `tools/verify_bundled_scenarios.ps1` plus package repository tests.
