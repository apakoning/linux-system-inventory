import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('report', ROOT / 'render-report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


class Report(unittest.TestCase):
    def test_overview_status_escaping_and_offline_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'summary.txt').write_text('Host: demo-host\n')
            (root / 'system-info.txt').write_text('PRETTY_NAME="RHEL example"\n')
            (root / 'cpu-info.txt').write_text('Model name: Example CPU\nCPU(s): 16\n<script>alert(1)</script>\n')
            (root / 'memory-info.txt').write_text('MemTotal: 67108864 kB\n')
            (root / 'collection-status.tsv').write_text('section\tstatus\tcommand\ncpu-info\tFAILED:124\tlscpu\n')
            output = report.render(root)
            content = output.read_text()
            self.assertIn('64.0 GiB', content)
            self.assertIn('demo-host', content)
            self.assertIn('Collector summary found', content)
            self.assertIn('No reinstall helper was generated', content)
            self.assertIn('FAILED:124', content)
            self.assertIn('&lt;script&gt;alert(1)&lt;/script&gt;', content)
            self.assertNotIn('<script>alert(1)</script>', content)
            self.assertNotIn('@@', content)
            self.assertNotIn('<script src=', content)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_render_only_works_without_collection(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(['/bin/bash', str(ROOT / 'system-inventory.sh'),
                                     '--render-only', directory], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((Path(directory) / 'index.html').exists())
            self.assertIn('Collector summary missing', (Path(directory) / 'index.html').read_text())
            self.assertIn('Collection completeness is unknown',
                          (Path(directory) / 'index.html').read_text())
