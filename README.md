# Realmz Rebuilt

Realmz Rebuilt is a greenfield, cross-platform Realmz runtime built with Godot 4.7.1. It models Castle Realmz behavior directly while keeping gameplay deterministic and independent of presentation timing. Providence compiles authored scenarios into immutable `.realmz2` packages; Rebuilt validates and runs those packages.

This is beta software. Keep backups of saves and character files, and expect compatibility fixes before the first stable release. Rebuilt intentionally retains the existing `RealmzRemake2` Godot user-data directory so current Rebuilt saves, settings, installed packages, and characters continue to be found. It does not import saves or campaign projects from the earlier host architecture.

## Get the source

Git LFS is required because the application library and bundled scenarios are LFS-backed packages.

```bash
git lfs install
git clone https://github.com/iSynic/Realmz-Rebuilt.git
cd Realmz-Rebuilt
git lfs pull
git lfs fsck
```

GitHub's Download ZIP is also supported. If a `.realmz2` file begins with `version https://git-lfs.github.com/spec/v1`, it is an LFS pointer rather than game data; use the Git/LFS clone method instead and report the archive problem.

## Run from Godot

1. Install the standard, non-.NET Godot 4.7.1 editor.
2. Import `project.godot` from the repository root.
3. Allow the initial asset import to finish.
4. Run the project with F6/F5 from the editor.

Native builds default to Godot's Mobile renderer, using the RenderingDevice path on supported Windows, Linux, and macOS systems. For older or problematic graphics hardware, run with the explicit OpenGL fallback:

```text
--rendering-method gl_compatibility --rendering-driver opengl3
```

The canonical interface target is 1280×720. Keyboard, mouse, and platform-standard window/fullscreen controls are supported; relevant gameplay commands are shown in the active workspace.

## Included content and licensing

Original Realmz Rebuilt source code is licensed under GPL-3.0-or-later. Realmz-derived scenarios, application assets, and the six Classic starter characters are separately licensed under CC BY-NC-SA 4.0 and are not relicensed by the GPL. Exact provenance, modifications, hashes, and third-party licenses are recorded in [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

The public repository includes the thirteen Castle-distributed scenarios authorized for Rebuilt: Assault on Giant Mountain, Castle in the Clouds, City of Bywater, Destroy the Necronomicon, Grilochs Revenge, Half Truth, Mithril Vault, Prelude to Pestilence, Trouble in the Sword Lands, Twin Sands of Time, War in the Sword Lands, White Dragon, and Wrath of the Mind Lords. The synthetic package is test-only.

On first start with no character-vault directory or a completely empty vault, Rebuilt installs deterministic editable copies of Kevlar, Lothlorian, Silver Leaf, Traskelion, Trevor, and Vormale. Any existing entry—valid or otherwise—suppresses starter installation so the application never overwrites a user's vault.

## Saves and local data

Godot stores Rebuilt data under its `RealmzRemake2` application directory:

- Windows: `%APPDATA%\Godot\app_userdata\RealmzRemake2`
- Linux: `~/.local/share/godot/app_userdata/RealmzRemake2`
- macOS: `~/Library/Application Support/Godot/app_userdata/RealmzRemake2`

The `saves`, `characters`, and `packages` subdirectories are user-owned. Copy the entire application directory before testing a beta on valuable playthroughs.

## Development and verification

Run the complete local verification lane from PowerShell 7:

```powershell
./tools/verify.ps1
```

Public architecture and fidelity contracts are documented in [docs/architecture.md](docs/architecture.md), [docs/package-and-save-contracts.md](docs/package-and-save-contracts.md), [docs/fidelity-ledger.md](docs/fidelity-ledger.md), and the ADRs under `docs/adr`. Contribution requirements are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Beta feedback

Use the [Beta bug report](https://github.com/iSynic/Realmz-Rebuilt/issues/new?template=beta_bug.yml). Include the platform, renderer, scenario, map coordinates or battle number, exact reproduction steps, relevant log, and save/package identity. Do not attach copyrighted scenarios that are not part of this repository or personal character/save data without reviewing it first.

Known Beta 1 limitations and release validation requirements are maintained in [docs/beta-1.md](docs/beta-1.md).
