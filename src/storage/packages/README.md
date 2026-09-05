# Package loading

Begin with `PackageRepository` when following installation or discovery, and with `PackageDomainAssembler` when following the conversion of verified JSON documents into immutable game content. The assembler coordinates public decoders and validators; it does not parse record families itself.

The thirteen release campaigns and their provenance records live in `bundled_campaigns/`. They are immutable package inputs discovered through the same validation and installation path as an external campaign; this directory does not grant them a runtime trust bypass.

`CanonicalJson` is the one stable dictionary encoder used for package hashes and exact repository readback comparisons. Character Files and settings reuse this storage utility rather than maintaining subtly different canonical encodings.

`PackageContentDecoder` is the stable content-record entry point. Campaign metadata, messages, and option labels belong to `PackageStoryContentDecoder`; items, Races, Castes, and spells belong to `PackageCharacterContentDecoder`; monsters, battles, treasures, shops, and encounters belong to `PackageEncounterContentDecoder`. Collection operations preserve authored order and duplicate tracking while focused record helpers validate and build one definition at a time. `PackageWorldDecoder` applies the same boundary to topology maps and Classic player maps, including exact media-backed marker validation. Scenario bytecode has its own neighboring decoder.

The flat Providence Caste record becomes a `CasteDefinition` with named attribute and progression sub-definitions at this boundary. The attribute record owns save, attribute, condition, and strength arrays; the progression record owns stamina, combat, magic, ability, and victory arrays. The decoder assigns the remaining scalar policy fields explicitly after validation, and no transport dictionary crosses into the game model.

`PackageScenarioDecoder` constructs Classic programs and Safe Scenario Actions. Safe bytecode remains a bounded recursive data format: the decoder routes calls, control flow, terminal instructions, scalar values, containers, operators, and collection expressions through named constructors while preserving one shared complexity counter and the declared-capability gate.

All decoders share one diagnostic dictionary and fail closed. Do not return transport dictionaries beyond this folder, invent defaults for malformed authored data, or copy stock application records into a scenario. Application content is composed first and the scenario contributes only owned records or exact-key overrides.

After composition and validation, `PackageDomainAssembler` builds `RealmzContent` as a directory of feature-owned immutable catalogs. Story and encounter triggers live under `content.scenario_records`; character definitions and appearance choices under `content.characters`; items under `content.items`; spells under `content.magic`; monsters and battles under `content.combat`; and shops and treasures under `content.economy`. Callers navigate to the owning catalog instead of asking `RealmzContent` to forward feature lookups. Portable item and spell identities therefore resolve against the same active application-plus-scenario catalogs used during package validation.

Cross-reference validation proceeds in authored dependency order: rule catalogs, Simple Encounters, Thief and Complex Encounters, then program instructions and destinations. Installation first recognizes a validated immutable target; a new target is copied to a temporary sibling, checked byte for byte, renamed atomically, receipted, and only then cached.

Package loading is startup-sensitive. Preserve receipt checks, parsed-document sidecars, bounded graph caching, and background installation. Run `tests/infrastructure/test_package_repository.gd` for decoder or validation work, `tests/infrastructure/test_package_install_task.gd` for worker lifecycle, and the full verification gate before changing a package contract.
