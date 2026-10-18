# Android tablet preview

This preview brings the bundled Realmz adventures to landscape Android tablets. It uses the same gameplay rules, campaigns, save format and six starter characters as the desktop game. It is a local testing build, separate from the desktop beta release.

## Keep your test saves

The app has its own private storage. Installing a newer preview over it with the same application ID and signing key preserves that storage. **Uninstalling the app or clearing its data deletes its saves, characters and internal backups.** Android cloud backup is disabled. Export and sharing are not available in this preview, so avoid using it for an irreplaceable long-term adventure.

Save explicitly when the game permits it. Going to the home screen pauses playback and input; returning resumes the existing session. Android may kill an app in the background. After that, load your last explicit save. Backgrounding does not create an autosave or enable saving during combat.

## Available content and controls

- The thirteen bundled campaigns, stock media and current starter characters are included. Character Files offers Restore starter characters and its ordinary repair workflow.
- Tap the existing controls. Touch holds use the existing map movement and command routes. Android Back follows the same local cancel/back and combat Auto safety behavior as Escape.
- Use the fixed HUD for initial tablet testing. Keyboard and controller support remain available, but hover, right-click and advanced modular arrangement are not claimed as complete touch workflows.
- External scenario, character artwork, font, music and saved-party file imports are disabled with a preview explanation. Local saves and Character Files remain usable. Desktop backup-folder opening is unavailable; verified backups remain inside the private sandbox.
- Bundled application music is available. Scenario-owned tracks that require the desktop music decoder are unavailable in this preview.

## Build and signing

Use Godot 4.7.1 with its matching Android release/debug export templates, JDK 17 and Android SDK build tools 35.0.1. The non-Gradle template declares minimum API 24 and target API 36. The APK contains ARM64 and x86_64 libraries; x86_64 supports emulator testing. The application ID is `org.realmz.rebuilt.preview`.

This preview explicitly uses OpenGL Compatibility. The desktop project keeps Mobile rendering as its default. Vulkan failed presentation on the tested Android emulator backends; physical tablet renderer performance remains unmeasured. Keep CRT and smoothing off for the first device check.

Run `tools/build_android_preview.ps1` with `-GodotExe`, `-TemplateRoot`, `-AndroidSdk`, `-JavaHome` and a new `-OutputDirectory`. Supply `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER` and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` through the process environment. Keep the keystore and password outside source control and release archives; retain the same key for future updates. Increment the Android version code for each distributed successor.

The builder uses isolated editor settings. `prepare_android_apk.py` stores Godot assets without outer ZIP compression so random-access package and resource reads do not repeatedly inflate Android compressed assets. The builder then performs 16-KiB-aware ZIP alignment and signs the final APK. Verification checks the signature, ZIP, application identity, SDK declarations, permissions, packaged architectures and byte-identical stock/campaign inputs. Source and tool hashes remain beside the APK. These packaging checks do not establish gameplay acceptance.

## Acceptance before handoff

Record the exact APK hash, emulator/device identity and actual interaction evidence for startup, starter availability, party assembly, adventure entry, movement, preferences, text entry, combat, explicit save/load and Android Back. Exercise background/resume during a held input and combat, process death/relaunch, and an APK update that preserves existing save and character bytes. Test inset geometry and captured releases independently. Keep synthetic input probes distinct from taps delivered to Android.

Two independent reviewers must each score the same frozen implementation at least 9.5/10 after inspecting source, package receipts, rendered screens, interactions and remaining limitations. Emulator success does not establish physical ARM tablet performance or touch comfort; those are the purpose of the subsequent tester handoff.
