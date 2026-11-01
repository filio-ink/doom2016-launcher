# Security changes in this fork

The 1.3.2 source build addresses the four findings from the 2026-10-31 review.

| Finding | Change |
| --- | --- |
| SEC-01: archive traversal | Reject absolute/parent paths and unsupported entries. Extract files before symlinks, reject symlink parents, resolve the final link graph, and install from private temporary staging. Failed extraction leaves the existing Wine untouched. |
| SEC-02: dependency provenance | Pin Wine 11.21, Python 3.14.10, CRT and the KosmicKrisp source ZIP/library in dependencies.json. Verify SHA-256 and size before use; publish downloads atomically. Recheck caches. Legacy Wine without a matching receipt is reinstalled. |
| SEC-03: GOG callback | Authenticate in the default system browser, then accept a manually pasted full HTTPS callback only for the exact host/path and current random state. Accept it once and clear it immediately. No embedded login browser or interception of Google credentials. |
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

## 1.3.2: browser-based sign-in

The embedded navigation allow-list introduced in 1.3.1 blocked Google's sign-in
navigation, and embedded WebViews are unsuitable for Google OAuth. Authentication
now runs in the system browser. This avoids blocked popups and preserves the
user's browser security context. The app requires an explicit paste of the full
GOG return URL because it cannot claim GOG's associated domain. It never reads
the clipboard in the background. Invalid origins, missing/wrong/duplicate state,
raw codes and replayed callbacks are rejected before exchanging a code.

References: [Google OAuth policies](https://developers.google.com/identity/protocols/oauth2/policies),
[Apple HTTPS callback domain requirement](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https(host:path:)).
