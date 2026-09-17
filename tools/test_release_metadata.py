"""Exercise release updates against isolated source/export fixtures."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from release_metadata import ROOT, load_release

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
            self.assertIn('const RELEASE_LABEL: String = "BETA 42"', result["src/shared/game_constants.gd"])
            self.assertIn("99 (binary packets 20)", result["docs/DEVELOPMENT.md"])
            exports = result["export_presets.cfg"]
            for filename in ("SuperStarFighter-Beta42.exe", "SuperStarFighter-Beta42.arm64", "SuperStarFighter-Beta42.x86_64", "SuperStarFighter-Beta42-macOS-universal.zip", "server/SuperStarFighter-Server.exe", "server-linux-arm64/SuperStarFighter-Server.arm64"):
                self.assertIn(f'export_path="builds/beta-42/{filename}"', exports)
            self.assertIn('application/file_version="1.2.3.42"', exports)
            self.assertIn('application/version="1.2.3.42"', exports)
            self.assertIn('application/short_version="1.2.3"', exports)

    def test_invalid_identity_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".tools") as directory:
            root = Path(directory)
            (root / "release.json").write_text(json.dumps({"version": "not-a-release", "protocol_version": 1, "packet_version": 1}))
            with self.assertRaises(ValueError):
                load_release(root)


if __name__ == "__main__":
    unittest.main()
