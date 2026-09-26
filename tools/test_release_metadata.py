"""Exercise release updates against isolated source/export fixtures."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from release_metadata import ROOT, load_release, render

spec = importlib.util.spec_from_file_location("update_release", ROOT / "tools/update-release-metadata.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class ReleaseMetadataTests(unittest.TestCase):
    def test_current_metadata_is_consistent(self):
        self.assertTrue(all(before == after for _, before, after in updater.updates()))

    def test_next_release_updates_all_targets(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".tools") as directory:
            root = Path(directory)
            paths = [path for path, _, _ in updater.updates()]
            for path in paths + ["release.json"]:
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / path, root / path)
            (root / "release.json").write_text(json.dumps({"version": "1.2.3-beta.42", "protocol_version": 99, "packet_version": 20}))
            result = {path: after for path, _, after in updater.updates(root)}
            self.assertIn('config/version="1.2.3-beta.42"', result["project.godot"])
            self.assertIn("const PROTOCOL_VERSION: int = 99", result["src/shared/game_constants.gd"])
            self.assertIn("const PACKET_VERSION: int = 20", result["src/shared/network/network_protocol.gd"])
            exports = result["export_presets.cfg"]
            self.assertIn('application/file_version="1.2.3.42"', exports)
            self.assertIn('application/version="1.2.3.42"', exports)
            self.assertIn('application/short_version="1.2.3"', exports)
            self.assertNotRegex(exports, r"(?i)beta ?\d|beta-\d")

    def test_documents_render_release_placeholders(self):
        release = load_release()
        text = render("{{LABEL}} {{VERSION}} SuperStarFighter-{{TAG}} protocol {{PROTOCOL}}/{{PACKET}}", release)
        self.assertEqual(text, f"{release['label']} {release['version']} SuperStarFighter-{release['tag']} "
                               f"protocol {release['protocol_version']}/{release['packet_version']}")
        with self.assertRaises(ValueError):
            render("{{UNKNOWN}}", release)
        for name in ("BETA_README.txt", "SERVER_README.txt"):
            rendered = render((ROOT / "docs" / name).read_text(encoding="utf-8"), release)
            self.assertIn(release["version"], rendered)
            self.assertNotIn("{{", rendered)

    def test_invalid_identity_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".tools") as directory:
            root = Path(directory)
            (root / "release.json").write_text(json.dumps({"version": "not-a-release", "protocol_version": 1, "packet_version": 1}))
            with self.assertRaises(ValueError):
                load_release(root)


if __name__ == "__main__":
    unittest.main()
