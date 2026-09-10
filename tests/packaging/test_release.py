import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_tag", ROOT / "scripts/validate-release-tag.py")
release_tag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_tag)


class ReleaseTagTests(unittest.TestCase):
    def test_accepts_matching_stable_versions(self):
        for version in ("0.13.2", "1.0.0", "12.34.56"):
            release_tag.validate(f"v{version}", version)

    def test_rejects_mismatched_bundle_version(self):
        with self.assertRaisesRegex(ValueError, "does not match"):
            release_tag.validate("v0.13.3", "0.13.2")

    def test_rejects_non_release_and_malformed_tags(self):
        for tag in ("main", "0.13.2", "v0.13", "v01.13.2", "v0.13.2-beta.1", "v0.13.2\n", "v0.13.2;echo bad"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release_tag.validate(tag, "0.13.2")

    def test_publication_requires_tag_push_and_successful_signing(self):
        workflow = (ROOT / ".github/workflows/signed-build.yml").read_text()
        publication = workflow.split("  publish-release:\n", 1)[1]
        self.assertIn("needs: signed-build", publication)
        self.assertIn("github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')", publication)
        self.assertNotIn("always()", publication)
        self.assertIn("--verify-tag", publication)
        self.assertNotIn("--clobber", publication)
        self.assertLess(publication.index("sha256sum --check"), publication.index("gh release create"))
