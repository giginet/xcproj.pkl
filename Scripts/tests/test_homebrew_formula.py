"""Check release retries and out-of-order releases without GitHub or Homebrew."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "update-homebrew-formula.py"


class HomebrewFormulaTests(unittest.TestCase):
    def test_retries_preserve_checksums_and_older_releases_cannot_downgrade(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "Formula/xcprojgen.rb"

            def generate(version, payload):
                archive = root / f"xcprojgen-{version}-macos-universal.tar.gz"
                archive.write_bytes(payload)
                return subprocess.run(
                    [sys.executable, str(SCRIPT), version, str(archive), "--output", str(output)],
                    capture_output=True, text=True,
                )

            initial = generate("1.2.3", b"first archive")
            self.assertEqual(initial.returncode, 0, initial.stderr)
            first = output.read_bytes()
            self.assertEqual(generate("1.2.3", b"first archive").returncode, 0)
            self.assertEqual(output.read_bytes(), first)
            self.assertEqual(generate("1.1.0", b"older archive").returncode, 0)
            self.assertEqual(output.read_bytes(), first)
            changed = generate("1.2.3", b"replaced archive")
            self.assertNotEqual(changed.returncode, 0)
            self.assertIn("refusing to change the checksum", changed.stderr)
            self.assertEqual(output.read_bytes(), first)
            self.assertEqual(generate("1.10.0", b"newer archive").returncode, 0)
            self.assertIn('version "1.10.0"', output.read_text())


if __name__ == "__main__":
    unittest.main()
