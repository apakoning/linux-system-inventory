import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1]/"system-inventory.sh"


class Inventory(unittest.TestCase):
    def test_cli_validation(self):
        for args,expected in [(["--help"],0),(["--version"],0),(["--output"],2),(["--invalid"],1)]:
            self.assertEqual(subprocess.run(["bash",str(SCRIPT),*args],capture_output=True).returncode,expected)

    def test_mock_collection_and_reinstall_helper(self):
        with tempfile.TemporaryDirectory() as d:
            base=Path(d);bin_dir=base/"bin";bin_dir.mkdir();out=base/"out"
            # Intercept every report's child shell: no real host inventory or network query.
            (bin_dir/"bash").write_text("#!/bin/sh\necho 'Mock collection report'\n")
            (bin_dir/"dnf").write_text("#!/bin/sh\nprintf 'bash\\ncoreutils\\n'\n")
            for p in bin_dir.iterdir():p.chmod(0o755)
            result=subprocess.run(["/bin/bash",str(SCRIPT),"--output",str(out),"--no-tar","--quiet"],env={**os.environ,"PATH":str(bin_dir)+os.pathsep+os.environ["PATH"]},capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            report=next(out.iterdir())
            self.assertEqual(report.stat().st_mode & 0o777,0o700)
            self.assertIn("Mock collection report",(report/"cpu-info.txt").read_text())
            self.assertTrue((report/"network-info.txt").exists())
            helper=report/"reinstall-dnf-userinstalled.sh"
            self.assertEqual(subprocess.run(["/bin/bash","-n",str(helper)]).returncode,0)
            self.assertIn("'coreutils'",helper.read_text())
            self.assertFalse(list(out.glob("*.tar.gz")))

    def test_unwritable_output_fails(self):
        with tempfile.TemporaryDirectory() as d:
            file=Path(d)/"file";file.write_text("not a directory")
            self.assertNotEqual(subprocess.run(["bash",str(SCRIPT),"--output",str(file)],capture_output=True).returncode,0)
