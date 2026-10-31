"""Pinned downloads and archive extraction shared by the launcher and builder."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import tempfile
import urllib.parse
import urllib.request
import zipfile

MANIFEST = json.loads(Path(__file__).with_name("dependencies.json").read_text(encoding="utf-8"))
MAX_ARCHIVE_FILES = 100_000
MAX_UNPACKED_BYTES = 4 * 1024**3


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verified_file(path: Path, spec: dict) -> bool:
    return (path.is_file() and not path.is_symlink()
            and path.stat().st_size == spec["size"]
            and sha256_file(path) == spec["sha256"])


class HTTPSRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        if urllib.parse.urlsplit(newurl).scheme != "https":
            raise ValueError("Refusing a dependency redirect without HTTPS")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def download_verified(spec: dict, destination: Path, progress=None) -> Path:
    """Verify before publishing; a failed download never becomes the cache."""
    if verified_file(destination, spec):
        return destination
    if urllib.parse.urlsplit(spec["url"]).scheme != "https":
        raise ValueError("Dependencies require HTTPS")
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=destination.name + ".", dir=destination.parent)
    partial = Path(name)
    try:
        request = urllib.request.Request(spec["url"], headers={"User-Agent": "doom-2016-secure"})
        opener = urllib.request.build_opener(HTTPSRedirects())
        received = 0
        digest = hashlib.sha256()
        with os.fdopen(descriptor, "wb") as output, opener.open(request, timeout=60) as response:
            if urllib.parse.urlsplit(response.geturl()).scheme != "https":
                raise ValueError("Dependency response did not use HTTPS")
            for block in iter(lambda: response.read(1024 * 1024), b""):
                received += len(block)
                if received > spec["size"]:
                    raise ValueError("Dependency exceeds its pinned size")
                output.write(block)
                digest.update(block)
                if progress:
                    progress(received, spec["size"])
        if received != spec["size"] or digest.hexdigest() != spec["sha256"]:
            raise ValueError("Dependency does not match its pinned SHA-256 and size")
        partial.replace(destination)
        return destination
    finally:
        partial.unlink(missing_ok=True)


def archive_parts(name: str) -> tuple[str, ...]:
    # Check before normalization: joining an absolute suffix discards staging.
    name = name.replace("\\", "/")
    if name.startswith("/") or "//" in name or ".." in name.split("/"):
        raise ValueError("Unsafe archive path")
    return PurePosixPath(name).parts


def extract_zip_dependency(archive_path: Path, destination: Path, spec: dict) -> None:
    # The original standalone KosmicKrisp URL is gone. Extract only the pinned
    # library from the author's signed 1.3 release, never its executable.
    with zipfile.ZipFile(archive_path) as archive:
        member = archive.getinfo(spec["zip_member"])
        if member.file_size != spec["member_size"]:
            raise ValueError("Unexpected dependency library size")
        target = destination / Path(spec["zip_member"]).name
        with archive.open(member) as source, target.open("xb") as output:
            shutil.copyfileobj(source, output)
        if sha256_file(target) != spec["member_sha256"]:
            raise ValueError("Dependency library does not match its pinned SHA-256")


def extract_tar(archive: tarfile.TarFile, destination: Path, prefix: tuple[str, ...], skip=None) -> None:
    """Write regular files first; archive symlinks never become write parents."""
    if destination.is_symlink() or any(destination.iterdir()):
        raise ValueError("Archive destination must be an empty real directory")
    root = destination.resolve()
    selected = []
    total = 0
    for index, member in enumerate(archive):
        if index >= MAX_ARCHIVE_FILES:
            raise ValueError("Too many archive entries")
        parts = archive_parts(member.name)
        if parts[:len(prefix)] != prefix:
            continue
        relative = parts[len(prefix):]
        if not relative or (skip and skip("/".join(relative))):
            continue
        if not (member.isdir() or member.isfile() or member.issym()):
            raise ValueError("Unsupported archive entry")
        total += member.size
        if total > MAX_UNPACKED_BYTES:
            raise ValueError("Archive exceeds the unpacked size limit")
        selected.append((member, root.joinpath(*relative)))
    links = []
    for member, target in selected:
        if member.issym():
            links.append((member, target))
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if member.isdir():
            target.mkdir(exist_ok=True)
            continue
        source = archive.extractfile(member)
        if source is None:
            raise ValueError("Missing archive file data")
        with source, target.open("xb") as output:
            shutil.copyfileobj(source, output)
        os.chmod(target, member.mode & 0o755)
    for member, target in links:
        if not member.linkname or member.linkname.startswith(("/", "\\")):
            raise ValueError("Absolute archive link")
        for parent in target.parents:
            if parent == root:
                break
            if parent.is_symlink():
                raise ValueError("Archive link has a symlink parent")
        target.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(member.linkname, target)
    # Resolve the whole graph after all links exist, including forward references.
    for _, target in links:
        try:
            try:
                resolved = target.resolve(strict=True)
            except FileNotFoundError:
                resolved = target.resolve()
            if not resolved.is_relative_to(root):
                raise ValueError("Archive link escapes the destination")
        except (OSError, RuntimeError) as error:
            raise ValueError("Invalid archive link") from error


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dependency", choices=MANIFEST)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--extract", type=Path)
    parser.add_argument("--prefix", default="")
    args = parser.parse_args()
    spec = MANIFEST[args.dependency]
    downloaded = download_verified(spec, args.destination)
    if args.extract:
        # Fresh private staging prevents pre-existing symlink traversal.
        args.extract.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="dependency-", dir=args.extract.parent) as temporary:
            staging = Path(temporary) / "payload"
            staging.mkdir(mode=0o700)
            if "zip_member" in spec:
                extract_zip_dependency(downloaded, staging, spec)
            else:
                with tarfile.open(downloaded) as archive:
                    extract_tar(archive, staging, archive_parts(args.prefix))
            if args.extract.exists():
                shutil.rmtree(args.extract)
            staging.rename(args.extract)


if __name__ == "__main__":
    main()
