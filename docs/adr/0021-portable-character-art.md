# 0021: Portable imported character artwork

Status: Accepted

Players can import named portraits and combat icons for creation and active characters. External paths cannot be durable character identities, and compiled scenario/application catalogs remain immutable.

Use `character-art:<role>:<PNG SHA-256>` in the existing portrait and combat-icon fields. The pure character catalog validates role-bound identity syntax; storage validates the selected image bytes. The managed library preserves originals and prepares native 44×44 portraits and 32×32 player icons with explicit Fit, square Crop or Resize and nearest-neighbor default sampling. Race/group names are library metadata only.

Save v5 and Character Files v2 add a strict optional `characterArt` bundle. It carries exactly the selected custom images, including unfinished creation selections in saves, and participates in the existing Character Files revision hash. Verify hash, image format, dimensions, bounds, metadata and complete reference closure before accepting a record. Stock-only records keep their previous shape; older save/character formats remain incompatible without migration.

The app host installs validated portable artwork before admission and supplies a separate read-only media port and detached choices to UI. Imported IDs never enter Classic exact-resource lookup, replace package content, change race/caste ownership, or consume gameplay RNG. Creation uses its existing typed transaction; active-character changes retain the existing draft and Apply boundary. Library imports persist independently from closing the modal.

Save, Character Files, creation, appearance and session-persistence suites cover existing boundaries. Import transformation and portable-image round trips additionally require direct scratch-repository verification and native-size rendered preview inspection.
