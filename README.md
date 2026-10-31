# DOOM (2016) on Mac — security fork

This is a small launcher for the GOG version of DOOM (2016). It is a bare-minimum Wine and Vulkan wrapper, and it uses KosmicKrisp. The game is not in the download.

You can point it at a GOG folder you already have, or install that copy from the app menu. The first launch downloads Wine and sets up the Windows side, including Microsoft's C++ runtime. On Apple silicon it also asks to install Rosetta if the Mac does not have it (requires an admin password).

<a href="https://www.youtube.com/watch?v=xcSXmYcd-Fg">
  <img src="https://img.youtube.com/vi/xcSXmYcd-Fg/hqdefault.jpg" width="480" alt="DOOM (2016) on Mac performance test">
</a>

[▶ Watch the M5 Pro and M4 performance test on YouTube](https://youtu.be/xcSXmYcd-Fg)

## Requirements
- Apple silicon Mac (M1 or later). Intel Macs are not supported.
- macOS 26 Tahoe or later. KosmicKrisp needs Metal 4, so it won't run on macOS 15 Sequoia or older.


## Install and run

This fork currently provides source builds. Build with the instructions below,
or unpack the patched application ZIP supplied alongside the source changes.
Move Doom2016GOG.app to Applications and open it. Local builds are ad-hoc signed;
a public notarized release requires the fork maintainer's own Developer ID.

Choose the GOG folder that contains DOOMx64vk.exe, or use Install Doom from GOG
in the app menu. Press Play. The first launch installs the pinned Wine and
Microsoft runtime after verifying their hashes. The game is not included.

Future signed updates are read from this fork's releases and must pass the
signature, Team ID, notarization and signed-version checks.

Xbox controllers already work. DualSense, DualSense Edge, and DualShock 4 pads are mapped so the game treats them as Xbox controllers. The button icons stay Xbox.

Macs before the M5 need a patched KosmicKrisp, which is included in this app. Stock KosmicKrisp refuses to create the Vulkan device on M4 because DOOM turns on `depthBounds` without asking whether the GPU has it.

There is also a Metal performance HUD, a way to try another Vulkan game with the same setup, a check for a newer launcher, and a GOG save sync in the app menu.


## Notes

- Tested on M5 Pro and M4 with macOS 27.
- The GOG download can sometimes stall. If it stops moving, pause or cancel it, then start it again. It downloads only the remaining files upon cancel/start.
- Full screen and Command-Tab do not get along. The game just closes. Borderless is the one that stays up when you switch apps.
- If the audio output device has 96Khz sampling rate then it causes static noise in the background. Setting sample rate to 48Khz in Audio Midi Setup app fixes it.
  

## Credits and licenses

DOOM (2016) is by id Software and Bethesda. It is not included. You need a GOG copy you own.

Wine is LGPL-2.1-or-later. The app downloads [Gcenx Wine 11.21](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.21) the first time it runs. Its exact archive size and SHA-256 are pinned in dependencies.json and checked before extraction. Previously installed Wine without a matching verification receipt is reinstalled.

Microsoft's Visual C++ 2015–2022 runtime is downloaded from Microsoft on that same first run. Wine's own copy of that runtime crashes this game.

KosmicKrisp is part of Mesa and is MIT. The patched build in this app is what lets the game create a Vulkan device on Macs before the M5. Mesa's notes are at [docs.mesa3d.org](https://docs.mesa3d.org/drivers/kosmickrisp.html).

The app downloads [gogdl](https://github.com/Heroic-Games-Launcher/heroic-gogdl) v1.3.1 from Heroic Games Launcher the first time you sign in to GOG, install the game, or sync saves. It is GPL-3.0, its download is checked against a SHA-256 hash, and it is used to sign in, download the game you own, and sync saves when you ask it to.

The launcher itself is MacGameTest. [youtube.com/@MacGameTest](https://www.youtube.com/@MacGameTest)

## Building this fork

Requires an Apple silicon Mac, Xcode/Swift with a macOS 26 SDK, and Python 3.10+.

```sh
bash scripts/test-security.sh
./build_app.sh
```

The result is dist/Doom2016GOG.app. By default the bundle and nested Python executables
are ad-hoc signed for local use; no Apple signing credentials are required. Gatekeeper
will not treat a downloaded copy as a notarized public release. A Developer ID release
requires SIGN_ID and a configured notarytool Keychain profile, then release.sh.
The built-in updater deliberately rejects ad-hoc or unnotarized replacement apps.
Updates default to filio-ink/doom2016-launcher. Explicitly setting UPDATE_REPOSITORY="" disables update checks; it never falls back to the upstream
repository. This fork uses bundle ID com.doom2016.secure.

Wine, Python, KosmicKrisp and the Microsoft runtime are pinned in dependencies.json. The build
re-verifies archives and re-extracts Python/KosmicKrisp before signing, including when
caches already exist. Changing a pin requires deliberately updating version, URL,
size and SHA-256 in that checked-in manifest. Do not obtain an expected checksum from
an untrusted download at runtime.

GOG callbacks require HTTPS, the exact embed.gog.com/on_login_success endpoint,
a matching one-time state and the main frame. GOG sign-in remains in an ephemeral
WKWebView because this project does not own GOG’s registered HTTPS redirect domain;
full sign-in must be tested with a real GOG account after changes. The launcher does
not weaken callback checks if the server omits state.

Regression checks cover archive traversal and symlink chains, checksum failures,
corrupted caches, legacy Wine receipts, GOG origins/state/frames and update rollback.

The upstream standalone KosmicKrisp release URL currently returns 404. This fork
extracts only libvulkan_kosmickrisp.dylib from the author's signed/notarized launcher
1.3 ZIP. Both the ZIP and the exact library bytes are pinned in dependencies.json;
the original launcher executable is never included or executed. Its library remains
covered by the existing Mesa MIT notice and license.
