#!/usr/bin/env python3
"""Tests for the one-item appcast writer and the tag-only release script."""

from __future__ import annotations

import json
import os
import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WRITER = ROOT / "Scripts" / "write-appcast.py"
PUBLISH = ROOT / "Scripts" / "publish-release.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "macos.yml"


class WriteAppcastTests(unittest.TestCase):
    def test_one_tag_writes_one_item_and_replaces_any_previous_feed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plist = directory / "Info.plist"
            dmg = directory / "Brian.dmg"
            output = directory / "appcast.json"
            _write_plist(plist, version="0.2.0", build="2", minimum="14.0")
            dmg.write_bytes(b"dmg-bytes")
            output.write_text('{"items":[{"version":"9.9.9"},{"version":"8.0.0"}]}\n', encoding="utf-8")
            notes = 'Line "one"\nLine two café'
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v0.2.0",
                "--repo",
                "embeputer/brian-desktop",
                "--notes",
                notes,
                "--output",
                str(output),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(
                payload,
                {
                    "items": [
                        {
                            "version": "0.2.0",
                            "build": "2",
                            "minimumSystemVersion": "14.0",
                            "downloadURL": "https://github.com/embeputer/brian-desktop/releases/download/v0.2.0/Brian.dmg",
                            "releaseNotes": notes,
                            "length": len(b"dmg-bytes"),
                        }
                    ]
                },
            )
            self.assertTrue(output.read_text(encoding="utf-8").endswith("\n"))

    def test_empty_notes_omit_the_field_and_integer_build_is_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plist = directory / "Info.plist"
            dmg = directory / "Brian.dmg"
            output = directory / "appcast.json"
            with plist.open("wb") as handle:
                plistlib.dump(
                    {
                        "CFBundleShortVersionString": "1",
                        "CFBundleVersion": 4,
                    },
                    handle,
                )
            dmg.write_bytes(b"x")
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v1",
                "--repo",
                "embeputer/brian-desktop",
                "--notes",
                "   ",
                "--output",
                str(output),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            item = json.loads(output.read_text(encoding="utf-8"))["items"][0]
            self.assertEqual(item["version"], "1")
            self.assertEqual(item["build"], "4")
            self.assertNotIn("releaseNotes", item)
            self.assertNotIn("minimumSystemVersion", item)
            self.assertEqual(
                item["downloadURL"],
                "https://github.com/embeputer/brian-desktop/releases/download/v1/Brian.dmg",
            )

    def test_tag_must_match_the_built_app_and_does_not_touch_the_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plist = directory / "Info.plist"
            dmg = directory / "Brian.dmg"
            output = directory / "appcast.json"
            _write_plist(plist, version="0.1.0", build="1", minimum="14.0")
            dmg.write_bytes(b"dmg")
            output.write_text("old\n", encoding="utf-8")
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v0.2.0",
                "--repo",
                "embeputer/brian-desktop",
                "--output",
                str(output),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("v0.2.0", result.stderr)
            self.assertIn("0.1.0", result.stderr)
            self.assertEqual(output.read_text(encoding="utf-8"), "old\n")

    def test_rejects_a_prerelease_version_an_empty_image_and_a_bad_repo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plist = directory / "Info.plist"
            dmg = directory / "Brian.dmg"
            output = directory / "appcast.json"
            _write_plist(plist, version="0.2.0-beta", build="2", minimum="14.0")
            dmg.write_bytes(b"dmg")
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v0.2.0-beta",
                "--repo",
                "embeputer/brian-desktop",
                "--output",
                str(output),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("dotted number", result.stderr)
            self.assertFalse(output.exists())

            _write_plist(plist, version="0.2.0", build="2", minimum="14.0")
            dmg.write_bytes(b"")
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v0.2.0",
                "--repo",
                "embeputer/brian-desktop",
                "--output",
                str(output),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("empty", result.stderr)

            dmg.write_bytes(b"dmg")
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v0.2.0",
                "--repo",
                "not a repo",
                "--output",
                str(output),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("owner/name", result.stderr)

    def test_refuses_an_update_larger_than_the_app_accepts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plist = directory / "Info.plist"
            dmg = directory / "Brian.dmg"
            output = directory / "appcast.json"
            _write_plist(plist, version="0.2.0", build="2", minimum="14.0")
            dmg.write_bytes(b"0123456789")
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v0.2.0",
                "--repo",
                "embeputer/brian-desktop",
                "--output",
                str(output),
                "--max-bytes",
                "10",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8"))["items"][0]["length"], 10)

            dmg.write_bytes(b"01234567890")
            result = _run_writer(
                "--plist",
                str(plist),
                "--dmg",
                str(dmg),
                "--tag",
                "v0.2.0",
                "--repo",
                "embeputer/brian-desktop",
                "--output",
                str(output),
                "--max-bytes",
                "10",
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("refuses updates", result.stderr)

    def test_reads_release_notes_from_the_github_response(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            response = Path(tmp) / "generate-notes.json"
            response.write_text(
                json.dumps({"name": "v0.2.0", "body": "  What changed.\n"}),
                encoding="utf-8",
            )
            result = subprocess.run(
                [sys.executable, str(WRITER), "--print-notes-from-github-json", str(response)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "What changed.\n")

            response.write_text("{}\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(WRITER), "--print-notes-from-github-json", str(response)],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)


class PublishReleaseTests(unittest.TestCase):
    def test_tag_push_creates_one_release_with_the_dmg_and_appcast(self) -> None:
        notes = 'Fixed "quotes"\nand a second line'
        with self._release_tree(version="0.2.0", build="2") as tree:
            result = tree.run(notes=notes)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(tree.commands(), ["api", "view", "create"])
            create = tree.invocation("create")
            self.assertIn("--latest", create)
            self.assertIn("--verify-tag", create)
            self.assertIn("--title", create)
            self.assertIn("v0.2.0", create)
            self.assertNotIn("--draft", create)
            self.assertNotIn("--prerelease", create)
            payload = json.loads((tree.capture / "appcast.json").read_text(encoding="utf-8"))
            self.assertEqual(len(payload["items"]), 1)
            item = payload["items"][0]
            self.assertEqual(item["version"], "0.2.0")
            self.assertEqual(item["build"], "2")
            self.assertEqual(item["minimumSystemVersion"], "14.0")
            self.assertEqual(item["releaseNotes"], notes)
            self.assertEqual(item["length"], len(b"dmg-bytes"))
            self.assertEqual(
                item["downloadURL"],
                "https://github.com/embeputer/brian-desktop/releases/download/v0.2.0/Brian.dmg",
            )
            self.assertEqual((tree.capture / "Brian.dmg").read_bytes(), b"dmg-bytes")
            self.assertEqual((tree.capture / "release-notes.txt").read_text(encoding="utf-8"), notes + "\n")

    def test_existing_release_is_updated_in_place(self) -> None:
        with self._release_tree(version="0.2.0", build="2") as tree:
            result = tree.run(exists=True)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            self.assertEqual(tree.commands(), ["api", "view", "upload", "edit"])
            upload = tree.invocation("upload")
            self.assertIn("--clobber", upload)
            edit = tree.invocation("edit")
            self.assertIn("--latest", edit)
            self.assertIn("--draft=false", edit)
            self.assertNotIn("create", tree.commands())

    def test_failed_release_notes_still_publish_the_disk_image(self) -> None:
        with self._release_tree(version="0.2.0", build="2") as tree:
            result = tree.run(api_fail=True)
            self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
            item = json.loads((tree.capture / "appcast.json").read_text(encoding="utf-8"))["items"][0]
            self.assertNotIn("releaseNotes", item)
            self.assertEqual((tree.capture / "release-notes.txt").read_text(encoding="utf-8"), "Brian 0.2.0\n")
            self.assertIn("create", tree.commands())

    def test_a_pull_request_or_main_push_does_not_call_github(self) -> None:
        cases = [
            {"GITHUB_EVENT_NAME": "pull_request", "GITHUB_REF": "refs/pull/4/merge", "GITHUB_REF_NAME": "4"},
            {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/heads/main", "GITHUB_REF_NAME": "main"},
            {"GITHUB_EVENT_NAME": "push", "GITHUB_REF": "refs/tags/v0.2.0", "GITHUB_REF_NAME": "v0.1.0"},
        ]
        for extra in cases:
            with self.subTest(extra=extra):
                with self._release_tree(version="0.2.0", build="2") as tree:
                    result = tree.run(**extra)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(tree.commands(), [])

    def test_a_version_mismatch_or_missing_token_does_not_call_github(self) -> None:
        with self._release_tree(version="0.1.0", build="1") as tree:
            result = tree.run(tag="v0.2.0")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("0.1.0", result.stderr)
            self.assertEqual(tree.commands(), [])

        with self._release_tree(version="0.2.0", build="2") as tree:
            result = tree.run(token=None)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("GH_TOKEN", result.stderr)
            self.assertEqual(tree.commands(), [])

    def test_this_checkout_does_not_contain_a_built_app_or_feed(self) -> None:
        self.assertFalse((ROOT / "Brian.dmg").exists())
        self.assertFalse((ROOT / "Brian.app").exists())
        self.assertFalse((ROOT / "appcast.json").exists())
        info = plistlib.loads((ROOT / "Scripts" / "Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "0.1.0")
        self.assertEqual(info["CFBundleVersion"], "1")

    def _release_tree(self, version: str, build: str) -> "_ReleaseTree":
        return _ReleaseTree(self, version, build)


class WorkflowTests(unittest.TestCase):
    def test_pull_requests_and_main_build_an_artifact_and_only_a_tag_publishes(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("pull_request:", text)
        self.assertIn("- main", text)
        self.assertIn('- "v*"', text)
        self.assertIn("runs-on: macos-latest", text)
        self.assertIn("./Scripts/package-dmg.sh", text)
        self.assertIn("actions/upload-artifact@v7", text)
        self.assertIn("name: Brian.dmg", text)
        self.assertIn("if-no-files-found: error", text)
        self.assertEqual(text.count("startsWith(github.ref, 'refs/tags/v')"), 1)
        self.assertEqual(text.count("./Scripts/publish-release.sh"), 1)
        self.assertLess(text.index("./Scripts/package-dmg.sh"), text.index("Upload the disk image"))
        self.assertLess(text.index("Upload the disk image"), text.index("Publish the GitHub release"))
        self.assertLess(
            text.index("startsWith(github.ref, 'refs/tags/v')"),
            text.index("./Scripts/publish-release.sh"),
        )
        self.assertNotIn("git commit", text)
        self.assertNotIn("git push", text)
        self.assertNotIn("workflow_dispatch:", text)
        mode = PUBLISH.stat().st_mode
        self.assertTrue(mode & stat.S_IXUSR)


class _ReleaseTree:
    def __init__(self, test: unittest.TestCase, version: str, build: str) -> None:
        self.test = test
        self.version = version
        self.build = build
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        scripts = self.root / "Scripts"
        scripts.mkdir()
        shutil.copy2(PUBLISH, scripts / "publish-release.sh")
        shutil.copy2(WRITER, scripts / "write-appcast.py")
        plist = self.root / "Brian.app" / "Contents" / "Info.plist"
        plist.parent.mkdir(parents=True)
        _write_plist(plist, version=version, build=build, minimum="14.0")
        (self.root / "Brian.dmg").write_bytes(b"dmg-bytes")
        self.fake_bin = self.root / "fake-bin"
        self.fake_bin.mkdir()
        self.log = self.root / "gh.log"
        self.capture = self.root / "capture"
        self.capture.mkdir()
        (self.fake_bin / "gh").write_text(_FAKE_GH, encoding="utf-8")
        (self.fake_bin / "gh").chmod(0o755)

    def __enter__(self) -> "_ReleaseTree":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self._tmp.cleanup()

    def run(
        self,
        notes: str = "What changed.",
        exists: bool = False,
        api_fail: bool = False,
        token: str | None = "fake-token",
        tag: str | None = None,
        **github: str,
    ) -> subprocess.CompletedProcess[str]:
        tag = tag or f"v{self.version}"
        env = {
            "PATH": f"{self.fake_bin}{os.pathsep}{os.environ.get('PATH', '')}",
            "HOME": os.environ.get("HOME", "/tmp"),
            "LANG": "C.UTF-8",
            "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
            "FAKE_GH_LOG": str(self.log),
            "FAKE_GH_CAPTURE": str(self.capture),
            "FAKE_GH_NOTES": notes,
            "FAKE_GH_EXISTS": "1" if exists else "0",
            "FAKE_GH_API_FAIL": "1" if api_fail else "0",
            "GITHUB_EVENT_NAME": "push",
            "GITHUB_REF": f"refs/tags/{tag}",
            "GITHUB_REF_NAME": tag,
            "GITHUB_REPOSITORY": "embeputer/brian-desktop",
        }
        if token is not None:
            env["GH_TOKEN"] = token
        env.update(github)
        return subprocess.run(
            ["bash", str(self.root / "Scripts" / "publish-release.sh")],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

    def commands(self) -> list[str]:
        if not self.log.exists():
            return []
        found = []
        for line in self.log.read_text(encoding="utf-8").splitlines():
            args = json.loads(line)
            if not args:
                continue
            if args[0] == "release" and len(args) > 1:
                found.append(args[1])
            else:
                found.append(args[0])
        return found

    def invocation(self, command: str) -> list[str]:
        for line in self.log.read_text(encoding="utf-8").splitlines():
            args = json.loads(line)
            if args[:1] == ["release"] and args[1:2] == [command]:
                return args
            if args[:1] == [command]:
                return args
        self.test.fail(f"gh {command} was not called")
        return []


def _write_plist(path: Path, version: str, build: str, minimum: str) -> None:
    with path.open("wb") as handle:
        plistlib.dump(
            {
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build,
                "LSMinimumSystemVersion": minimum,
            },
            handle,
        )


def _run_writer(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(WRITER), *args],
        text=True,
        capture_output=True,
        check=False,
    )


_FAKE_GH = textwrap.dedent(
    """\
    #!/usr/bin/env python3
    import json
    import os
    import shutil
    import sys
    from pathlib import Path

    log = Path(os.environ["FAKE_GH_LOG"])
    capture = Path(os.environ["FAKE_GH_CAPTURE"])
    args = sys.argv[1:]
    with log.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(args) + "\\n")
    previous = ""
    for arg in args:
        path = Path(arg)
        if path.is_file():
            shutil.copy(path, capture / path.name)
        if previous == "--notes-file" and path.is_file():
            shutil.copy(path, capture / "release-notes.txt")
        previous = arg
    if not args:
        sys.exit(1)
    command = args[0]
    if command == "api":
        if os.environ.get("FAKE_GH_API_FAIL") == "1":
            sys.exit(1)
        json.dump({"name": "release", "body": os.environ.get("FAKE_GH_NOTES", "")}, sys.stdout)
        sys.stdout.write("\\n")
        sys.exit(0)
    if command == "release" and len(args) > 1:
        sub = args[1]
        if sub == "view":
            sys.exit(0 if os.environ.get("FAKE_GH_EXISTS") == "1" else 1)
        if sub in {"create", "upload", "edit"}:
            sys.exit(0)
    sys.stderr.write("unexpected gh invocation\\n")
    sys.exit(99)
    """
)


if __name__ == "__main__":
    unittest.main()
