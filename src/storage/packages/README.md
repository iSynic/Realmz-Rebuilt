# Package loading

Begin with `PackageRepository` when following installation or discovery, and with `PackageDomainAssembler` when following the conversion of verified JSON documents into immutable game content. The assembler coordinates public decoders and validators; it does not parse record families itself.

`PackageContentDecoder` is the stable content-record entry point. Campaign metadata, messages, and option labels belong to `PackageStoryContentDecoder`; items, Races, Castes, and spells belong to `PackageCharacterContentDecoder`; monsters, battles, treasures, shops, and encounters belong to `PackageEncounterContentDecoder`. World topology and scenario bytecode have their own neighboring decoders.

All decoders share one diagnostic dictionary and fail closed. Do not return transport dictionaries beyond this folder, invent defaults for malformed authored data, or copy stock application records into a scenario. Application content is composed first and the scenario contributes only owned records or exact-key overrides.

Package loading is startup-sensitive. Preserve receipt checks, parsed-document sidecars, bounded graph caching, and background installation. Run `tests/infrastructure/test_package_repository.gd` for decoder or validation work, `tests/infrastructure/test_package_install_task.gd` for worker lifecycle, and the full verification gate before changing a package contract.
