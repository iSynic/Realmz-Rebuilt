# Music importer

This import-time helper validates MP3 and Ogg Vorbis directly and converts WAV,
FLAC, AIFF, MOD, XM, S3M, and IT to finite Vorbis audio. MAD is unsupported.
Players need no separately installed codecs or command-line tools.

Build from the repository root with PowerShell 7 and CMake 3.24 or newer:

```powershell
./tools/build_music_importer.ps1
```

Windows requires Visual Studio 2022 C++ tools and a Windows SDK. Linux requires
a C++ compiler, Ninja or Make, autoconf, automake, libtool, pkg-config, and the
usual build utilities. macOS requires Xcode command-line tools and those build
utilities. Use `-Triplet x64-linux`, `x64-osx`, or `arm64-osx` explicitly when
building another supported native target on its host. The default output is
`music-importer/`; `-OutputDirectory` selects a packaging stage.

The script fetches the exact vcpkg commit in `vcpkg.json`, builds its pinned
libopenmpt/libsndfile dependencies, and embeds a hash of the five native build
inputs. `--version` exposes this identity. The output manifest pins the binary
and copied dependency copyright files. Windows uses a static C/C++ runtime;
codec libraries are linked statically on all supported targets.

Run generated-input integration verification with explicit local tools:

```powershell
python tools/music_importer/test_importer.py --helper <absolute-helper> --ffmpeg <absolute-ffmpeg> --scratch artifacts/music-importer/new-run
```

FFmpeg is a verifier-only fixture generator. The application never invokes it.
The helper accepts an absolute input path, an existing empty output directory,
a display name, and a new result path. It writes a versioned JSON result; failure
returns nonzero. It renders each tracker subsong once with automatic repeat
disabled. Limits are 256 MiB input and each output, 32 subsongs, 30 minutes per
tracker subsong, two hours aggregate audio, and 110 seconds processing time.
The host enforces a separate two-minute process limit and owns cancellation,
staging cleanup, immutable originals, and atomic library publication.
