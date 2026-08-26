#!/usr/bin/env python3
"""Extract one MKV Magic CI runtime archive without trusting tar paths or modes."""

from __future__ import annotations

import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile


MAX_MEMBERS = 4096
MAX_UNCOMPRESSED_BYTES = 1024 * 1024 * 1024
EXPECTED_ROOT = "mkv-magic-ci-runtime"


def fail(message: str) -> "NoReturn":
    raise SystemExit(message)


def validated_relative_path(name: str) -> PurePosixPath:
    trimmed = name[:-1] if name.endswith("/") else name
    if not trimmed or trimmed.startswith("/") or "\\" in trimmed or "//" in trimmed:
        fail("CI runtime archive contains an unsafe path")
    relative = PurePosixPath(trimmed)
    if not relative.parts or relative.parts[0] != EXPECTED_ROOT:
        fail("CI runtime archive has an unexpected root")
    if any(part in {"", ".", ".."} for part in relative.parts):
        fail("CI runtime archive contains path traversal")
    return relative


def extract(archive: Path, destination: Path) -> None:
    if not archive.is_absolute() or not archive.is_file() or archive.is_symlink():
        fail("CI runtime archive is missing or unsafe")
    if not destination.is_absolute() or destination.exists() or destination.is_symlink():
        fail("CI runtime extraction destination must be an absent absolute path")

    with tarfile.open(archive, "r:gz") as tar:
        members = tar.getmembers()
        if not members or len(members) > MAX_MEMBERS:
            fail("CI runtime archive member count is invalid")
        total_size = 0
        seen: set[PurePosixPath] = set()
        validated: list[tuple[tarfile.TarInfo, PurePosixPath]] = []
        for member in members:
            relative = validated_relative_path(member.name)
            if relative in seen:
                fail("CI runtime archive contains duplicate paths")
            seen.add(relative)
            if not member.isdir() and not member.isfile():
                fail("CI runtime archive contains a link or special file")
            if member.isfile():
                if member.size <= 0:
                    fail("CI runtime archive contains an empty file")
                total_size += member.size
                if total_size > MAX_UNCOMPRESSED_BYTES:
                    fail("CI runtime archive exceeds its size limit")
            validated.append((member, relative))

        destination.mkdir(mode=0o755)
        for member, relative in sorted(validated, key=lambda item: len(item[1].parts)):
            target = destination.joinpath(*relative.parts)
            if member.isdir():
                target.mkdir(mode=0o755, parents=True, exist_ok=True)
                continue
            target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
            source = tar.extractfile(member)
            if source is None:
                fail("CI runtime archive file could not be read")
            mode = 0o755 if member.mode & 0o111 else 0o644
            descriptor = os.open(
                target,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                mode,
            )
            with source, os.fdopen(descriptor, "wb") as output:
                shutil.copyfileobj(source, output)


def main() -> None:
    if len(sys.argv) != 3:
        fail("usage: extract-ci-runtime.py <absolute-archive.tar.gz> <absolute-destination>")
    extract(Path(sys.argv[1]), Path(sys.argv[2]))


if __name__ == "__main__":
    main()
