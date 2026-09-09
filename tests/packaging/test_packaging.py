import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
TEST_BASH = os.environ.get("MARKER_TEST_BASH", "/bin/bash")


class ScriptFixture(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.bin_dir = self.root / "stub-bin"
        self.bin_dir.mkdir()
        self.command_log = self.root / "commands.log"

    def tearDown(self):
        self.temp_dir.cleanup()

    def stub(self, name, body):
        path = self.bin_dir / name
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def environment(self):
        environment = os.environ.copy()
        environment["PATH"] = f"{self.bin_dir}:{environment['PATH']}"
        environment["STUB_COMMAND_LOG"] = str(self.command_log)
        environment["STUB_XCRUN_LOG"] = str(self.root / "xcrun.log")
        return environment

    def make_build_fixture(self):
        shutil.copy2(REPO_ROOT / "build-app.sh", self.root / "build-app.sh")
        (self.root / "Resources" / "en.lproj").mkdir(parents=True)
        (self.root / "Resources" / "Info.plist").write_text("<plist/>\n")
        (self.root / "Resources" / "AppIcon.icns").write_bytes(b"icon")
        (self.root / "Resources" / "en.lproj" / "Localizable.strings").write_text("")
        (self.root / "Sources" / "Marker").mkdir(parents=True)
        (self.root / "Sources" / "Marker" / "MarkerApp.swift").write_text("// fixture\n")
        (self.root / ".build" / "artifacts" / "Sparkle.framework").mkdir(parents=True)

        self.stub(
            "swift",
            """
mkdir -p .build/release .build/arm64-apple-macosx/release/Marker.build
: > .build/release/Marker
: > .build/release/marker-cli
: > .build/arm64-apple-macosx/release/Marker.build/Marker.swiftconstvalues
""",
        )
        self.stub(
            "xcrun",
            """
printf '%s\\n' "$*" >> "$STUB_XCRUN_LOG"
if [[ "${1:-}" == "--show-sdk-path" ]]; then
  echo /stub/MacOSX.sdk
  exit 0
fi
output=""
while (($#)); do
  if [[ "$1" == "--output" ]]; then
    output="$2"
    break
  fi
  shift
done
mkdir -p "$output/Metadata.appintents"
: > "$output/Metadata.appintents/extract.actionsdata"
""",
        )
        self.stub(
            "xcode-select",
            "echo \"${STUB_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}\"\n",
        )
        self.stub("xcodebuild", "printf 'Xcode 16.0\\nBuild version 16A000\\n'\n")
        self.stub("pgrep", "exit 1\n")
        self.stub("install_name_tool", ":\n")
        self.stub("codesign", "printf '%s\\n' \"$*\" >> \"$STUB_COMMAND_LOG\"\n")

    def run_script(self, *arguments):
        return subprocess.run(
            [TEST_BASH, str(self.root / "build-app.sh"), *arguments],
            cwd=self.root,
            env=self.environment(),
            text=True,
            capture_output=True,
        )


class BuildAppSigningTests(ScriptFixture):
    def test_refuses_symlinked_build_directory_and_preserves_external_app(self):
        self.make_build_fixture()

        with tempfile.TemporaryDirectory() as external_temp_dir:
            external_build = Path(external_temp_dir)
            sentinel = external_build / "Marker.app" / "sentinel.txt"
            sentinel.parent.mkdir()
            sentinel.write_text("keep me\n")
            (self.root / "build").symlink_to(external_build, target_is_directory=True)

            result = self.run_script()

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlinked build directory", result.stderr)
            self.assertEqual(sentinel.read_text(), "keep me\n")
            self.assertFalse(self.command_log.exists())

    def test_ad_hoc_signing_requires_the_explicit_test_flag(self):
        self.make_build_fixture()

        default_result = self.run_script()
        self.assertEqual(default_result.returncode, 0, default_result.stderr)
        default_calls = self.command_log.read_text().splitlines()
        self.assertEqual(len(default_calls), 3)
        self.assertTrue(all("--timestamp --sign Developer ID Application" in call for call in default_calls))

        self.command_log.write_text("")
        test_result = self.run_script("--test-ad-hoc-sign")
        self.assertEqual(test_result.returncode, 0, test_result.stderr)
        test_calls = self.command_log.read_text().splitlines()
        self.assertEqual(len(test_calls), 3)
        self.assertTrue(all("--sign -" in call for call in test_calls))
        self.assertTrue(all("--timestamp" not in call for call in test_calls))
        self.assertIn("TEST-ONLY ad-hoc signing", test_result.stderr)

    def test_app_intents_uses_the_selected_xcode_toolchain(self):
        self.make_build_fixture()
        environment = self.environment()
        environment["STUB_DEVELOPER_DIR"] = "/Applications/Xcode_16.4.app/Contents/Developer"

        result = subprocess.run(
            [TEST_BASH, str(self.root / "build-app.sh")],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "--toolchain-dir /Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain",
            (self.root / "xcrun.log").read_text(),
        )

    def test_rejects_every_argument_except_the_exact_test_flag(self):
        self.make_build_fixture()

        for arguments in [("",), ("--ad-hoc",), ("--test-ad-hoc-sign", "extra")]:
            with self.subTest(arguments=arguments):
                result = self.run_script(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertIn("Usage:", result.stderr)


class TestDmgPackagingTests(ScriptFixture):
    def make_package_fixture(self):
        (self.root / "scripts").mkdir()
        shutil.copy2(
            REPO_ROOT / "scripts" / "package-test-dmg.sh",
            self.root / "scripts" / "package-test-dmg.sh",
        )
        build_script = self.root / "build-app.sh"
        build_script.write_text(
            """#!/bin/bash
set -euo pipefail
printf '%s\\n' "$*" > build-arguments.log
if [[ "${STUB_BUILD_FAIL:-0}" == "1" ]]; then
  exit 42
fi
mkdir -p build/Marker.app/Contents/{MacOS,Resources/Metadata.appintents,Frameworks/Sparkle.framework}
: > build/Marker.app/Contents/MacOS/Marker
if [[ "${STUB_SKIP_CLI:-0}" != "1" ]]; then
  : > build/Marker.app/Contents/MacOS/marker-cli
fi
: > build/Marker.app/Contents/Info.plist
: > build/Marker.app/Contents/Resources/Metadata.appintents/extract.actionsdata
"""
        )
        build_script.chmod(build_script.stat().st_mode | stat.S_IXUSR)

        self.stub("uname", "echo \"${STUB_ARCH:-arm64}\"\n")
        self.stub("git", "echo 0123456789abcdef0123456789abcdef01234567\n")
        self.stub(
            "codesign",
            """
printf 'codesign %s\\n' "$*" >> "$STUB_COMMAND_LOG"
if [[ "$1" == "--display" ]]; then
  if [[ "${STUB_SIGNATURE_KIND:-adhoc}" == "adhoc" ]]; then
    echo 'Signature=adhoc' >&2
  else
    echo 'Authority=Developer ID Application: Fixture' >&2
  fi
fi
""",
        )
        self.stub(
            "hdiutil",
            """
printf 'hdiutil %s\\n' "$*" >> "$STUB_COMMAND_LOG"
if [[ "$1" == "create" ]]; then
  source_folder=""
  output="${!#}"
  while (($#)); do
    if [[ "$1" == "-srcfolder" ]]; then
      source_folder="$2"
      break
    fi
    shift
  done
  python3 - "$source_folder" "$STUB_LAYOUT_LOG" <<'PY'
import os
import sys

source_folder, layout_log = sys.argv[1:]
entries = []
for directory, directory_names, file_names in os.walk(source_folder, followlinks=False):
    for name in directory_names + file_names:
        entries.append(os.path.relpath(os.path.join(directory, name), source_folder))
with open(layout_log, "w", encoding="utf-8") as output:
    for entry in sorted(entries):
        print(entry, file=output)
PY
  readlink "$source_folder/Applications" > "$STUB_LINK_LOG"
  cp "$source_folder/TEST-BUILD-WARNING.txt" "$STUB_WARNING_COPY"
  cp "$source_folder/PROVENANCE.txt" "$STUB_PROVENANCE_COPY"
  printf 'fixture DMG bytes\n' > "$output"
elif [[ "$1" == "verify" ]]; then
  [[ -f "$2" ]]
  if [[ "${STUB_HDIUTIL_VERIFY_FAIL:-0}" == "1" ]]; then
    exit 55
  fi
else
  exit 64
fi
""",
        )
    def package_environment(self):
        environment = self.environment()
        environment["STUB_LAYOUT_LOG"] = str(self.root / "layout.log")
        environment["STUB_LINK_LOG"] = str(self.root / "link.log")
        environment["STUB_WARNING_COPY"] = str(self.root / "warning.txt")
        environment["STUB_PROVENANCE_COPY"] = str(self.root / "provenance.txt")
        return environment

    def test_refuses_symlinked_build_directory_and_preserves_external_outputs(self):
        self.make_package_fixture()

        with tempfile.TemporaryDirectory() as external_temp_dir:
            external_build = Path(external_temp_dir)
            sentinels = []
            for generated_path in ("Marker.app", "test-dist", "test-dmg-staging"):
                sentinel = external_build / generated_path / "sentinel.txt"
                sentinel.parent.mkdir()
                sentinel.write_text("keep me\n")
                sentinels.append(sentinel)
            (self.root / "build").symlink_to(external_build, target_is_directory=True)

            result = subprocess.run(
                [TEST_BASH, "scripts/package-test-dmg.sh"],
                cwd=self.root,
                env=self.package_environment(),
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("symlinked build directory", result.stderr)
            for sentinel in sentinels:
                self.assertEqual(sentinel.read_text(), "keep me\n")
            self.assertFalse((self.root / "build-arguments.log").exists())

    def test_checksum_verifies_after_flat_artifact_download(self):
        self.make_package_fixture()

        result = subprocess.run(
            [TEST_BASH, "scripts/package-test-dmg.sh"],
            cwd=self.root,
            env=self.package_environment(),
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        dmg = self.root / "build/test-dist/Marker-arm64-TEST-unnotarized-0123456789ab.dmg"
        checksum = Path(f"{dmg}.sha256")
        with tempfile.TemporaryDirectory() as download_temp_dir:
            download_dir = Path(download_temp_dir)
            downloaded_dmg = download_dir / dmg.name
            downloaded_checksum = download_dir / checksum.name
            shutil.copy2(dmg, downloaded_dmg)
            shutil.copy2(checksum, downloaded_checksum)

            verification = subprocess.run(
                ["/usr/bin/shasum", "-a", "256", "-c", downloaded_checksum.name],
                cwd=download_dir,
                text=True,
                capture_output=True,
            )

            self.assertEqual(verification.returncode, 0, verification.stderr)
            self.assertIn(f"{downloaded_dmg.name}: OK", verification.stdout)

    def test_creates_traceable_test_only_dmg_with_expected_layout(self):
        self.make_package_fixture()

        result = subprocess.run(
            [TEST_BASH, "scripts/package-test-dmg.sh"],
            cwd=self.root,
            env=self.package_environment(),
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        dmg = self.root / "build/test-dist/Marker-arm64-TEST-unnotarized-0123456789ab.dmg"
        self.assertTrue(dmg.is_file())
        self.assertTrue(Path(f"{dmg}.sha256").is_file())
        self.assertEqual((self.root / "build-arguments.log").read_text(), "--test-ad-hoc-sign\n")
        layout = (self.root / "layout.log").read_text().splitlines()
        self.assertIn("Marker.app", layout)
        self.assertIn("Applications", layout)
        self.assertIn("TEST-BUILD-WARNING.txt", layout)
        self.assertIn("PROVENANCE.txt", layout)
        self.assertFalse(any(entry.startswith("Applications/") for entry in layout))
        self.assertEqual((self.root / "link.log").read_text(), "/Applications\n")
        warning = (self.root / "warning.txt").read_text()
        self.assertIn("TEST build", warning)
        self.assertIn("NOT notarized", warning)
        self.assertIn("not an isolated profile", warning)
        self.assertIn("normal history and settings", warning)
        self.assertIn("replace an installed copy of Marker", warning)
        self.assertIn("Gatekeeper", warning)
        self.assertIn("TCC", warning)
        provenance = (self.root / "provenance.txt").read_text()
        self.assertIn("0123456789abcdef0123456789abcdef01234567", provenance)
        command_log = self.command_log.read_text()
        self.assertIn("codesign --verify --deep --strict", command_log)
        self.assertIn(f"hdiutil verify {dmg.relative_to(self.root)}", command_log)

    def test_rejects_a_non_ad_hoc_app_signature(self):
        self.make_package_fixture()
        environment = self.package_environment()
        environment["STUB_SIGNATURE_KIND"] = "developer-id"

        result = subprocess.run(
            [TEST_BASH, "scripts/package-test-dmg.sh"],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected an ad-hoc app signature", result.stderr)
        command_log = self.command_log.read_text()
        self.assertIn("codesign --display --verbose=4", command_log)
        self.assertNotIn("hdiutil create", command_log)

    def test_propagates_dmg_verification_failure_and_removes_partial_image(self):
        self.make_package_fixture()
        environment = self.package_environment()
        environment["STUB_HDIUTIL_VERIFY_FAIL"] = "1"

        result = subprocess.run(
            [TEST_BASH, "scripts/package-test-dmg.sh"],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 55)
        dmg = self.root / "build/test-dist/Marker-arm64-TEST-unnotarized-0123456789ab.dmg"
        self.assertFalse(dmg.exists())
        self.assertFalse(Path(f"{dmg}.sha256").exists())
        self.assertIn("hdiutil verify", self.command_log.read_text())

    def test_stops_when_a_required_app_bundle_file_is_missing(self):
        self.make_package_fixture()
        environment = self.package_environment()
        environment["STUB_SKIP_CLI"] = "1"

        result = subprocess.run(
            [TEST_BASH, "scripts/package-test-dmg.sh"],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Required app bundle file missing: build/Marker.app/Contents/MacOS/marker-cli",
            result.stderr,
        )
        command_log = self.command_log.read_text() if self.command_log.exists() else ""
        self.assertNotIn("codesign", command_log)
        self.assertNotIn("hdiutil", command_log)

    def test_propagates_builder_failure_without_creating_an_image(self):
        self.make_package_fixture()
        environment = self.package_environment()
        environment["STUB_BUILD_FAIL"] = "1"

        result = subprocess.run(
            [TEST_BASH, "scripts/package-test-dmg.sh"],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 42)
        dmg = self.root / "build/test-dist/Marker-arm64-TEST-unnotarized-0123456789ab.dmg"
        self.assertFalse(dmg.exists())
        command_log = self.command_log.read_text() if self.command_log.exists() else ""
        self.assertNotIn("hdiutil", command_log)

    def test_rejects_a_non_arm64_runner_before_building(self):
        self.make_package_fixture()
        environment = self.package_environment()
        environment["STUB_ARCH"] = "x86_64"

        result = subprocess.run(
            [TEST_BASH, "scripts/package-test-dmg.sh"],
            cwd=self.root,
            env=environment,
            text=True,
            capture_output=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires an arm64 macOS runner", result.stderr)
        self.assertFalse((self.root / "build-arguments.log").exists())


class WorkflowContractTests(unittest.TestCase):
    def test_ci_packages_and_uploads_only_the_test_artifact(self):
        workflow = (REPO_ROOT / ".github/workflows/ci.yml").read_text()

        tests_at = workflow.index("- name: Run tests")
        checks_at = workflow.index("- name: Run packaging checks")
        package_at = workflow.index("- name: Package arm64 TEST DMG")
        upload_at = workflow.index("- name: Upload TEST DMG")
        summary_at = workflow.index("- name: Summarize TEST artifact")
        self.assertLess(tests_at, checks_at)
        self.assertLess(checks_at, package_at)
        self.assertLess(package_at, upload_at)
        self.assertLess(upload_at, summary_at)

        self.assertIn("python3 -m unittest discover -s tests/packaging -v", workflow)
        self.assertIn("run: scripts/package-test-dmg.sh", workflow)
        upload_block = workflow[upload_at:summary_at]
        self.assertIn(
            "uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
            upload_block,
        )
        self.assertIn("build/test-dist/*.dmg", upload_block)
        self.assertIn("build/test-dist/*.dmg.sha256", upload_block)
        self.assertNotIn("build/**", upload_block)
        self.assertNotIn("build/\n", upload_block)
        self.assertIn("retention-days: 7", upload_block)
        self.assertIn("if-no-files-found: error", upload_block)
        self.assertNotIn("continue-on-error", workflow)
        self.assertNotIn("secrets.", workflow)
        self.assertNotIn("pull_request_target:", workflow)
        self.assertIn("permissions:\n  contents: read", workflow)

        summary_block = workflow[summary_at:]
        self.assertIn("TEST ONLY", summary_block)
        self.assertIn("ad-hoc signed", summary_block)
        self.assertIn("not notarized", summary_block)
        self.assertIn("actions/runs/${GITHUB_RUN_ID}#artifacts", summary_block)


if __name__ == "__main__":
    unittest.main()
