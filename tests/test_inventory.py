import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'system-inventory.sh'


class Inventory(unittest.TestCase):
    def test_cli_validation(self):
        for args, expected in [(['--help'], 0), (['--version'], 0),
                               (['--output'], 2), (['--invalid'], 1),
                               (['--appimage-depth', '-1'], 1)]:
            self.assertEqual(subprocess.run(['/bin/bash', str(SCRIPT), *args],
                                            capture_output=True).returncode, expected)

    def collect(self, base, *, archive=False, dnf_failure=False, tar_failure=False):
        bin_dir = base / 'bin'
        bin_dir.mkdir()
        # Block real inventory/network calls while exercising collector functions.
        names = ('hostname hostnamectl lscpu free lsblk lspci lsusb df mount ip '
                 'resolvectl ss rpm flatpak snap find fc-list python3 npm cargo '
                 'go gem systemctl gnome-extensions uname firewall-cmd getenforce '
                 'sestatus cat ls').split()
        for name in names:
            (bin_dir / name).write_text('#!/bin/sh\necho "mock $0"\n')
        (bin_dir / 'lscpu').write_text('#!/bin/sh\necho "cpu unavailable" >&2\nexit 7\n')
        (bin_dir / 'dnf').write_text('#!/bin/sh\n' + (
            'echo "query failed" >&2\nexit 9\n' if dnf_failure else
            'printf "bash\\ncoreutils\\n"\n'))
        if tar_failure:
            (bin_dir / 'tar').write_text('#!/bin/sh\nexit 2\n')
        for path in bin_dir.iterdir():
            path.chmod(0o755)
        home = base / 'home'
        home.mkdir()
        out = base / 'output with spaces'
        result = subprocess.run(
            ['/bin/bash', str(SCRIPT), '--output', str(out), '--quiet',
             *([] if archive else ['--no-tar'])],
            env={**os.environ, 'HOME': str(home),
                 'PATH': str(bin_dir) + os.pathsep + os.environ['PATH']},
            capture_output=True, text=True)
        report = next(p for p in out.iterdir() if p.is_dir())
        return result, report

    def test_collection_status_and_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            result, report = self.collect(Path(directory))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(report.stat().st_mode & 0o777, 0o700)
            self.assertIn('FAILED:7', (report / 'collection-status.tsv').read_text())
            self.assertIn('cpu unavailable', (report / 'cpu-info.txt').read_text())
            helper = report / 'reinstall-dnf-userinstalled.sh'
            self.assertEqual(subprocess.run(['/bin/bash', '-n', str(helper)]).returncode, 0)
            self.assertIn('  coreutils', helper.read_text())
            self.assertIn(str(report), result.stdout)
            self.assertTrue((report / 'python-pip-visible-packages.txt').exists())

    def test_query_failure_omits_helper(self):
        with tempfile.TemporaryDirectory() as directory:
            result, report = self.collect(Path(directory), dnf_failure=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((report / 'reinstall-dnf-userinstalled.sh').exists())
            self.assertTrue((report / 'reinstall-helper-unavailable.txt').exists())

    def test_failed_archive_preserves_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            result, report = self.collect(Path(directory), archive=True, tar_failure=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((report / 'summary.txt').exists())
            self.assertIn('reports retained', result.stderr)

    def test_archive_contains_reports_and_keeps_directory(self):
        import tarfile
        with tempfile.TemporaryDirectory() as directory:
            result, report = self.collect(Path(directory), archive=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            with tarfile.open(str(report) + '.tar.gz') as archive:
                self.assertIn(report.name + '/summary.txt', archive.getnames())
            self.assertTrue(report.is_dir())

    def test_unwritable_output_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'file'
            path.write_text('not a directory')
            self.assertNotEqual(subprocess.run(
                ['/bin/bash', str(SCRIPT), '--output', str(path)],
                capture_output=True).returncode, 0)
