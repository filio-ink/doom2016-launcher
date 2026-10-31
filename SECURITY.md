# Security changes in this fork

The 1.3.1 source build addresses the four findings from the 2026-10-31 review.

| Finding | Change |
| --- | --- |
| SEC-01: archive traversal | Reject absolute/parent paths and unsupported entries. Extract files before symlinks, reject symlink parents, resolve the final link graph, and install from private temporary staging. Failed extraction leaves the existing Wine untouched. |
| SEC-02: dependency provenance | Pin Wine 11.21, Python 3.14.10, CRT and the KosmicKrisp source ZIP/library in dependencies.json. Verify SHA-256 and size before use; publish downloads atomically. Recheck caches. Legacy Wine without a matching receipt is reinstalled. |
| SEC-03: GOG callback | Require HTTPS, the exact callback host/path, main frame, and a unique matching state parameter. Use ephemeral WebKit storage and restrict main-frame navigation. |
| SEC-04: update rollback | Validate the signed bundle version against the offered version and require it to exceed the current version, both after extraction and before handoff. Retain signature, Team ID and notarization checks. |

Swift UI and bundled Python no longer receive Wine's JIT, unsigned executable
memory or library-validation exceptions. They are separate processes from Wine.
The embedded Python ignores Python environment overrides and user site packages.

Run regression checks with:

```sh
bash scripts/test-security.sh
```

The real pinned Wine archive was also verified and extracted successfully without
executing Wine. The built arm64 application opens its main window, the bundled
Python runs the launcher CLI, and codesign --verify --deep --strict passes.

Local builds are ad-hoc signed, not notarized Developer ID releases. Their updater
does not bypass its trust checks. This fork does not have credentials for GOG or
a licensed game in its source; complete GOG authorization, installation of the
Microsoft runtime, and DOOM gameplay require a separate test with an owned copy.
An unauthenticated GOG authorization request preserved the supplied state on the
login page; the final authenticated redirect has not been tested.

The original standalone KosmicKrisp URL is unavailable. The library is taken from
the author's launcher 1.3 release, whose Developer ID signature and stapled ticket
were verified during preparation. The build downloads only that pinned ZIP and
extracts only the pinned library; it does not execute the original launcher.
