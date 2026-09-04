# Package loading

Begin with `PackageRepository` when following installation or discovery, and with `PackageDomainAssembler` when following the conversion of verified JSON documents into immutable game content. The assembler coordinates public decoders and validators; it does not parse record families itself.

`PackageContentDecoder` is the stable content-record entry point. Campaign metadata, messages, and option labels belong to `PackageStoryContentDecoder`; items, Races, Castes, and spells belong to `PackageCharacterContentDecoder`; monsters, battles, treasures, shops, and encounters belong to `PackageEncounterContentDecoder`. Collection operations preserve authored order and duplicate tracking while focused record helpers validate and build one definition at a time. `PackageWorldDecoder` applies the same boundary to topology maps and Classic player maps, including exact media-backed marker validation. Scenario bytecode has its own neighboring decoder.

`PackageScenarioDecoder` constructs Classic programs and Safe Scenario Actions. Safe bytecode remains a bounded recursive data format: the decoder routes calls, control flow, terminal instructions, scalar values, containers, operators, and collection expressions through named constructors while preserving one shared complexity counter and the declared-capability gate.

All decoders share one diagnostic dictionary and fail closed. Do not return transport dictionaries beyond this folder, invent defaults for malformed authored data, or copy stock application records into a scenario. Application content is composed first and the scenario contributes only owned records or exact-key overrides.

Cross-reference validation proceeds in authored dependency order: rule catalogs, Simple Encounters, Thief and Complex Encounters, then program instructions and destinations. Installation first recognizes a validated immutable target; a new target is copied to a temporary sibling, checked byte for byte, renamed atomically, receipted, and only then cached.

Package loading is startup-sensitive. Preserve receipt checks, parsed-document sidecars, bounded graph caching, and background installation. Run `tests/infrastructure/test_package_repository.gd` for decoder or validation work, `tests/infrastructure/test_package_install_task.gd` for worker lifecycle, and the full verification gate before changing a package contract.
