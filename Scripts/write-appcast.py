#!/usr/bin/env python3
"""Write the one-item appcast for a single Brian release tag.

The app reads releases/latest/download/appcast.json and refuses an archive
whose version does not match the item. This writer emits exactly one item,
for the tag being published, using the built app's version and build.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
from pathlib import Path

# ReleaseFeed.downloadIsAcceptable drops an item whose length exceeds this.
MAXIMUM_DOWNLOAD_BYTES = 250_000_000
VERSION_PATTERN = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")
BUILD_PATTERN = re.compile(r"^[0-9]+$")
REPO_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


class AppcastError(Exception):
    """The release cannot be described with a feed the app will install."""


def write_appcast(
    plist_path: Path,
    dmg_path: Path,
    tag: str,
    repo: str,
    output_path: Path,
    notes: str = "",
    max_bytes: int = MAXIMUM_DOWNLOAD_BYTES,
) -> dict:
    info = _read_plist(plist_path)
    version = _plist_text(info, "CFBundleShortVersionString")
    build = _plist_text(info, "CFBundleVersion")
    minimum = _plist_text(info, "LSMinimumSystemVersion")
    if not version or not build:
        raise AppcastError("The built app is missing CFBundleShortVersionString or CFBundleVersion.")
    if VERSION_PATTERN.fullmatch(version) is None:
        raise AppcastError(
            f"CFBundleShortVersionString {version!r} is not a dotted number such as 0.2.0."
        )
    if BUILD_PATTERN.fullmatch(build) is None:
        raise AppcastError(f"CFBundleVersion {build!r} is not a whole number.")
    if tag != f"v{version}":
        raise AppcastError(
            f"Tag {tag} does not match the built app version {version} (CFBundleShortVersionString). "
            f"This build is published with tag v{version}. "
            "Bump Scripts/Info.plist before tagging a different version."
        )
    if REPO_PATTERN.fullmatch(repo) is None:
        raise AppcastError(f"Repository {repo!r} is not an owner/name GitHub repo.")
    if minimum and VERSION_PATTERN.fullmatch(minimum) is None:
        raise AppcastError(
            f"LSMinimumSystemVersion {minimum!r} is not a dotted number such as 14.0."
        )
    if not dmg_path.is_file():
        raise AppcastError(f"Missing disk image: {dmg_path}")
    length = dmg_path.stat().st_size
    if length <= 0:
        raise AppcastError("Brian.dmg is empty.")
    if length > max_bytes:
        raise AppcastError(
            f"Brian.dmg is {length} bytes. The app refuses updates larger than {max_bytes} bytes."
        )

    item = {
        "version": version,
        "build": build,
    }
    if minimum:
        item["minimumSystemVersion"] = minimum
    item["downloadURL"] = f"https://github.com/{repo}/releases/download/{tag}/Brian.dmg"
    notes = notes.strip()
    if notes:
        item["releaseNotes"] = notes
    item["length"] = length
    payload = {"items": [item]}
    output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return payload


def notes_from_github_response(response_path: Path) -> str:
    try:
        payload = json.loads(response_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise AppcastError(f"Could not read GitHub release notes: {error}") from error
    if not isinstance(payload, dict):
        raise AppcastError("GitHub release notes were not a JSON object.")
    body = payload.get("body")
    if not isinstance(body, str):
        return ""
    return body.strip()


def _read_plist(path: Path) -> dict:
    try:
        value = plistlib.loads(path.read_bytes())
    except (OSError, plistlib.InvalidFileException, ValueError) as error:
        raise AppcastError(f"Could not read {path}: {error}") from error
    if not isinstance(value, dict):
        raise AppcastError(f"Could not read {path}: the plist is not a dictionary.")
    return value


def _plist_text(info: dict, key: str) -> str:
    value = info.get(key)
    if isinstance(value, bool) or value is None:
        return ""
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        return value.strip()
    return ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Write one appcast.json item for a Brian release tag.")
    parser.add_argument("--plist", type=Path, help="Built Brian.app Contents/Info.plist")
    parser.add_argument("--dmg", type=Path, help="Path to Brian.dmg")
    parser.add_argument("--tag", help="Release tag, such as v0.2.0")
    parser.add_argument("--repo", help="GitHub repository, owner/name")
    parser.add_argument("--output", type=Path, help="Where to write appcast.json")
    parser.add_argument("--notes", default="", help="Release notes. Empty omits the field.")
    parser.add_argument("--notes-file", type=Path, help="File containing release notes.")
    parser.add_argument(
        "--print-notes-from-github-json",
        type=Path,
        help="Print the body from a generate-notes API response and exit.",
    )
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=MAXIMUM_DOWNLOAD_BYTES,
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args(argv)
    try:
        if args.print_notes_from_github_json is not None:
            text = notes_from_github_response(args.print_notes_from_github_json)
            if not text:
                raise AppcastError("GitHub returned no release notes.")
            sys.stdout.write(text)
            if not text.endswith("\n"):
                sys.stdout.write("\n")
            return 0
        missing = [
            name
            for name, value in (
                ("--plist", args.plist),
                ("--dmg", args.dmg),
                ("--tag", args.tag),
                ("--repo", args.repo),
                ("--output", args.output),
            )
            if value is None
        ]
        if missing:
            raise AppcastError(f"Missing {' '.join(missing)}.")
        if args.notes and args.notes_file is not None:
            raise AppcastError("Pass release notes with --notes or --notes-file, not both.")
        notes = args.notes
        if args.notes_file is not None:
            try:
                notes = args.notes_file.read_text(encoding="utf-8")
            except (OSError, UnicodeError) as error:
                raise AppcastError(f"Could not read release notes: {error}") from error
        write_appcast(
            plist_path=args.plist,
            dmg_path=args.dmg,
            tag=args.tag,
            repo=args.repo,
            output_path=args.output,
            notes=notes,
            max_bytes=args.max_bytes,
        )
    except AppcastError as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
