# Custom music

Open Music from Settings or Preferences to import MP3, Ogg Vorbis, WAV, FLAC, AIFF, MOD, XM, S3M, and IT. The library copies originals, so moving the source files afterward does not affect playback. MAD is not supported.

Create a playlist, add tracks, reorder them, and choose ordered or shuffled playback with Repeat All, Repeat One, or no repeat. Assign it to Outdoor, Battle, Shop, or another context globally or for the current scenario. Inherit uses the global choice; Original music explicitly uses the authored or stock track. Apply saves playlists and assignments; Done saves and closes; Cancel discards that draft. Imports, removals, volume, and Play/Continue/Off apply immediately.

Continue leaves the current queue advancing. Off suspends it. Returning to a context resumes its queue during this application session. Preview temporarily suspends normal music; Stop preview restores it. Repair cache reimports a track's managed original. Import errors and unavailable-track diagnostics remain in the Library panel.

Scenario-owned tracker music is prepared automatically through the same bundled decoder when its original music is selected. The first preparation runs in the background; later playback reuses a hash-validated cache stored separately from the player library. Scenario tracks retain their authored Custom slot, title, and looping. Preparation does not modify packages, saves, or playlist assignments, and completion respects the currently selected music context, Off, Continue, and preview. Unavailable or unsupported scenario music reports a diagnostic in Music.

## Native build

`tools/music_importer/vcpkg.json` pins the complete dependency baseline. Build with CMake, Git, PowerShell 7, and a C++17 toolchain: Visual Studio 2022 C++ on Windows, GCC/Clang plus the usual vcpkg build prerequisites on Linux, or Xcode command-line tools on macOS.

Windows verification and release jobs use the `windows-2022` runner image to retain the required Visual Studio 2022 toolchain. macOS format probes use Homebrew's keg-only `ffmpeg-full` executable for its Vorbis encoder; the reduced `ffmpeg` formula does not provide that fixture encoder.

```powershell
./tools/build_music_importer.ps1 -Triplet x64-windows-static
./tools/build_music_importer.ps1 -Triplet x64-linux
./tools/build_music_importer.ps1 -Triplet x64-osx -OutputDirectory build/music-x64
./tools/build_music_importer.ps1 -Triplet arm64-osx -OutputDirectory build/music-arm64
./tools/package_music_importer.ps1 -Target macos-universal -InputDirectory build/music-x64,build/music-arm64 -OutputDirectory build/music-universal
```

Run only the command for the matching build host; macOS runs both architecture builds and packaging. Windows/Linux packaging uses `-Target windows` or `linux` with one input directory. Output directories for packaging must be new. The source hash covers CMake, the dependency manifest, and helper sources. Each helper reports it through `--version`; packaging records exact executable and license hashes in `manifest.json`. Universal packages retain the union of both architectures' notices, including host build-tool notices, and reject conflicting bytes at a shared license path.

Distribute the `music-importer` directory beside the game executable, or under `Realmz Rebuilt.app/Contents/MacOS/` on macOS. CI and tagged-release workflows build and package it. Static codec libraries eliminate external codec-tool installation; FFmpeg is used only to generate development fixtures. Retain dependency copyright files and make the pinned library source/build recipe available with source distribution, including the LGPL dependencies' relinking terms.

## Verification

Run the focused infrastructure music-library and presentation music-system/playback suites. `tools/music_importer/test_importer.py --helper ABSOLUTE_BINARY --ffmpeg ABSOLUTE_FFMPEG --scratch ABSOLUTE_NEW_ARTIFACTS_DIRECTORY` generates all nine format probes, Unicode and misleading paths, damaged inputs, and cancellation evidence. Its tracker tones test decoding, not Castle fidelity. Native export verification checks helper identity, exact hashes, licenses, and platform target. Native Linux/macOS execution and listening acceptance must be reported separately from Windows or automated PCM checks.

The Windows export has passed artifact validation and fresh-profile startup with a restricted runtime PATH. Windows and Linux native helpers have passed all nine synthetic format imports; Linux dependency inspection found only standard system runtime libraries. Isolated actual controls have exercised import, playlist creation, global assignment, Apply, and cache repair without changing the gameplay snapshot. All three tabs were inspected at 1280×720 and 800×600 with 100% and 150% text, using the shared slate chrome. Full native Linux/macOS export acceptance and subjective listening checks remain outstanding; CI now runs the format probes for each native packaging target.
