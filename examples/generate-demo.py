#!/usr/bin/env python3
"""Generate the public HTML example using fictional data, never host inventory."""
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('report', ROOT / 'render-report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)
DATA = {
    'summary.txt': 'Host: example-workstation\nGenerated: Fictional demonstration · not a live machine\n',
    'system-info.txt': 'PRETTY_NAME="Red Hat Enterprise Linux 9 · fictional example"\nStatic hostname: example-workstation\nKernel: Linux 5.14.0\nArchitecture: x86-64\n',
    'cpu-info.txt': 'Architecture: x86_64\nCPU(s): 16\nModel name: Example 8-core workstation processor\nThread(s) per core: 2\nCore(s) per socket: 8\n',
    'memory-info.txt': 'MemTotal:       67108864 kB\nMemAvailable:   48234496 kB\nSwapTotal:       8388608 kB\n',
    'filesystem-usage.txt': 'Filesystem Type Size Used Avail Use% Mounted on\n/dev/example-root xfs 200G 72G 128G 36% /\n/dev/example-home xfs 720G 418G 302G 58% /home\n/dev/example-backup ext4 3.6T 2.4T 1.2T 67% /mnt/backup\n',
    'rpm-all-packages.txt': 'bash 5.1.8-9.el9.x86_64\ncoreutils 8.32-39.el9.x86_64\npython3 3.9.21-2.el9.x86_64\nvim-enhanced 8.2.2637-22.el9.x86_64\n',
    'dnf-modules.txt': 'Error: Cache-only enabled but no cache available for example-repository.\nFAILED: exit status 1\n',
    'network-info.txt': 'Example data only\nlo: loopback\nenp1s0: UP\n    inet 192.0.2.10/24\ndefault via 192.0.2.1 dev enp1s0\n',
    'running-systemd-services.txt': 'UNIT                    LOAD   ACTIVE SUB     DESCRIPTION\nsshd.service            loaded active running OpenSSH server daemon\nNetworkManager.service  loaded active running Network Manager\n',
    'snap-packages.txt': 'SKIPPED: command unavailable: snap\n',
    'collection-status.tsv': 'section\tstatus\tcommand\nsystem-info\tOK\thostnamectl\ncpu-info\tOK\tlscpu\nmemory-info\tOK\tfree\nfilesystem-usage\tOK\tdf\nrpm-all-packages\tOK\trpm\ndnf-modules\tFAILED:1\tdnf module list\nnetwork-info\tOK\tip\nrunning-systemd-services\tOK\tsystemctl\nsnap-packages\tSKIPPED\tsnap\n',
}
with tempfile.TemporaryDirectory() as directory:
    temp = Path(directory)
    for name, text in DATA.items():
        (temp / name).write_text(text)
    output = report.render(temp)
    (ROOT / 'examples' / 'sample-report.html').write_text(output.read_text())
