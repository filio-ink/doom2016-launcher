#!/usr/bin/env python3
"""Package the built app and verify the mounted DMG without launching it."""
from pathlib import Path
import hashlib
import os
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
APP = DIST / "Doom2016GOG.app"


def run(*arguments):
    subprocess.run(arguments, check=True)


def main():
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}(?:[-+][A-Za-z0-9.-]+)?", version):
        raise ValueError("Invalid application version")
    dmg = DIST / f"DOOM-2016-Secure-{version}-arm64.dmg"
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(APP))
    with tempfile.TemporaryDirectory(prefix="dmg-stage-", dir=DIST) as temporary:
        staging = Path(temporary)
        run("/usr/bin/ditto", str(APP), str(staging / APP.name))
        os.symlink("/Applications", staging / "Applications")
        (staging / "Установка.txt").write_text(
            f"DOOM (2016) Secure {version}\n\n"
            "Перетащите Doom2016GOG.app в Applications (Программы).\n"
            "Apple Silicon, macOS 26 или новее. Игра не включена.\n"
            "Установка игры: File → Install Doom from GOG…\n"
            "Вход: Open GOG in Browser → авторизация в браузере.\n"
            "Полный итоговый адрес из браузера вставьте только в поле лаунчера.\n"
            "Сборка подписана ad-hoc, без notarization Apple.\n"
            "Исходники: https://github.com/filio-ink/doom2016-launcher\n",
            encoding="utf-8",
        )
        run("/usr/bin/hdiutil", "create", "-volname", "DOOM 2016 Secure",
            "-fs", "HFS+", "-srcfolder", str(staging), "-format", "UDZO",
            "-imagekey", "zlib-level=9", "-ov", str(dmg))
    run("/usr/bin/hdiutil", "verify", str(dmg))
    with tempfile.TemporaryDirectory(prefix="doom-dmg-check-") as temporary:
        mounted = False
        try:
            run("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse",
                "-mountpoint", temporary, str(dmg))
            mounted = True
            app = Path(temporary) / APP.name
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
            if (app / "Contents/Info.plist").read_bytes() != (APP / "Contents/Info.plist").read_bytes():
                raise ValueError("Packaged application metadata differs")
            if os.readlink(Path(temporary) / "Applications") != "/Applications":
                raise ValueError("Incorrect installation link")
            run(str(app / "Contents/Resources/python/bin/python3"), "-B", "-E", "-s",
                str(app / "Contents/Resources/engine/launch.py"), "--help")
        finally:
            if mounted:
                run("/usr/bin/hdiutil", "detach", temporary)
    checksum = hashlib.sha256()
    with dmg.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(block)
    digest = checksum.hexdigest()
    dmg.with_suffix(".dmg.sha256").write_text(f"{digest}  {dmg.name}\n")
    print(f"Verified DMG: {dmg}")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
