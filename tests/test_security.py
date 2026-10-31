import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import dependencies
import launch


def spec_for(data):
    return dict(version="fixture", url="https://example.invalid/archive",
                size=len(data), sha256=hashlib.sha256(data).hexdigest())


class Response(io.BytesIO):
    def geturl(self):
        return "https://example.invalid/archive"


class DownloadTests(unittest.TestCase):
    def test_zip_dependency_extracts_only_the_pinned_member(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root / "source.zip"
            output = root / "out"
            output.mkdir()
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr("../outside", b"ignore")
                zipped.writestr("app/lib.dylib", b"verified")
            spec = dict(zip_member="app/lib.dylib", member_size=8,
                        member_sha256=hashlib.sha256(b"verified").hexdigest())
            dependencies.extract_zip_dependency(archive, output, spec)
            self.assertEqual((output / "lib.dylib").read_bytes(), b"verified")
            self.assertFalse((root / "outside").exists())
            spec["member_sha256"] = "0" * 64
            bad_output = root / "bad"
            bad_output.mkdir()
            with self.assertRaises(ValueError):
                dependencies.extract_zip_dependency(archive, bad_output, spec)

    def test_verified_cache_does_not_request_network(self):
        with tempfile.TemporaryDirectory() as folder:
            cached = Path(folder) / "archive"
            cached.write_bytes(b"verified")
            with patch("urllib.request.build_opener") as opener:
                dependencies.download_verified(spec_for(b"verified"), cached)
            opener.assert_not_called()

    def test_corrupted_cache_is_replaced_only_after_verification(self):
        with tempfile.TemporaryDirectory() as folder:
            cached = Path(folder) / "archive"
            cached.write_bytes(b"corrupt!")
            with patch("urllib.request.build_opener") as opener:
                opener.return_value.open.return_value = Response(b"verified")
                dependencies.download_verified(spec_for(b"verified"), cached)
            self.assertEqual(cached.read_bytes(), b"verified")

    def test_bad_hash_and_oversize_preserve_old_cache_and_remove_partial(self):
        for incoming in (b"tampered", b"too much data"):
            with self.subTest(incoming=incoming), tempfile.TemporaryDirectory() as folder:
                cached = Path(folder) / "archive"
                cached.write_bytes(b"old")
                with patch("urllib.request.build_opener") as opener:
                    opener.return_value.open.return_value = Response(incoming)
                    with self.assertRaises(ValueError):
                        dependencies.download_verified(spec_for(b"verified"), cached)
                self.assertEqual(cached.read_bytes(), b"old")
                self.assertEqual(list(Path(folder).iterdir()), [cached])

    def test_refuses_http_source_and_redirect(self):
        with tempfile.TemporaryDirectory() as folder:
            spec = spec_for(b"data")
            spec["url"] = "http://example.invalid/archive"
            with self.assertRaises(ValueError):
                dependencies.download_verified(spec, Path(folder) / "archive")
        with self.assertRaises(ValueError):
            dependencies.HTTPSRedirects().redirect_request(None, None, 302, "", {}, "http://example.invalid/")


class ArchiveTests(unittest.TestCase):
    def fixture(self, path, entries):
        with tarfile.open(path, "w:xz") as archive:
            for name, content, kind in [
                ("payload/bin/wine", b"inert wine", "file"),
                ("payload/bin/wineserver", b"inert server", "file"),
                *entries,
            ]:
                info = tarfile.TarInfo(name)
                info.mode = 0o777
                if kind == "file":
                    info.size = len(content)
                    archive.addfile(info, io.BytesIO(content))
                else:
                    info.type = tarfile.SYMTYPE if kind == "symlink" else tarfile.LNKTYPE
                    info.linkname = content
                    archive.addfile(info)

    def install(self, archive, destination):
        spec = spec_for(archive.read_bytes())
        with patch.object(launch, "WINE_SPEC", spec):
            return launch.install_wine_archive(archive, "fixture", destination)

    def test_normal_archive_and_safe_link(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root / "archive.tar.xz"
            self.fixture(archive, [("payload/bin/wine64", "wine", "symlink")])
            destination = self.install(archive, root / "wine")
            self.assertEqual((destination / "bin/wine64").read_bytes(), b"inert wine")
            self.assertEqual((destination / "bin/wine").stat().st_mode & 0o777, 0o755)
            self.assertTrue((destination / ".verified-sha256").is_file())

    def test_absolute_suffix_and_dotdot_cannot_escape_or_replace_install(self):
        for attack in ("absolute", "dotdot"):
            with self.subTest(attack=attack), tempfile.TemporaryDirectory() as folder:
                root = Path(folder).resolve()
                destination = root / "wine"
                destination.mkdir()
                (destination / "old.txt").write_text("keep")
                victim = root / "outside.txt"
                victim.write_text("original")
                member = "payload/" + str(victim) if attack == "absolute" else "payload/../outside.txt"
                archive = root / "archive.tar.xz"
                self.fixture(archive, [(member, b"overwritten", "file")])
                with self.assertRaises(ValueError):
                    self.install(archive, destination)
                self.assertEqual(victim.read_text(), "original")
                self.assertEqual((destination / "old.txt").read_text(), "keep")

    def test_symlink_chain_never_becomes_a_write_parent(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder).resolve()
            archive = root / "archive.tar.xz"
            self.fixture(archive, [
                ("payload/b", ".", "symlink"),
                ("payload/a", "b/..", "symlink"),
                ("payload/a/outside.txt", b"escape", "file"),
            ])
            with self.assertRaises((ValueError, FileExistsError)):
                self.install(archive, root / "wine")
            self.assertFalse((root / "outside.txt").exists())

    def test_outside_and_cyclic_links_are_rejected(self):
        for target in ("..", "/tmp", "link"):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                archive = root / "archive.tar.xz"
                self.fixture(archive, [("payload/link", target, "symlink")])
                with self.assertRaises(ValueError):
                    self.install(archive, root / "wine")
                self.assertFalse((root / "wine").exists())

    def test_hardlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root / "archive.tar.xz"
            self.fixture(archive, [("payload/link", "payload/bin/wine", "hardlink")])
            with self.assertRaises(ValueError):
                self.install(archive, root / "wine")

    def test_legacy_or_wrong_receipt_is_not_trusted(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "bin").mkdir()
            (root / "bin/wine").touch()
            (root / "bin/wineserver").touch()
            with patch.object(launch, "INSTALLED_WINE", root):
                self.assertIsNone(launch.installed_wine())
                (root / ".verified-sha256").write_text("wrong")
                self.assertIsNone(launch.installed_wine())
                (root / ".verified-sha256").write_text(launch.WINE_SPEC["sha256"])
                self.assertEqual(launch.installed_wine(), root)

    def test_wrong_archive_hash_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root / "archive.tar.xz"
            self.fixture(archive, [])
            with self.assertRaises(ValueError):
                launch.install_wine_archive(archive, launch.WINE_SPEC["version"], root / "wine")
            self.assertFalse((root / "wine").exists())


if __name__ == "__main__":
    unittest.main()
