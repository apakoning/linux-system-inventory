# Linux System Inventory

[![Checks](https://github.com/apakoning/linux-system-inventory/actions/workflows/checks.yml/badge.svg)](https://github.com/apakoning/linux-system-inventory/actions/workflows/checks.yml)

**Know your machine. See what was collected. Find the detail you need.**

A Bash inventory collector for RHEL and related RPM/DNF systems, with a self-contained HTML report. Inspect hardware, software, services and collection diagnostics from one searchable page. Keep the raw text for terminal work and support.

*Fictional demonstration data. [Download the example HTML](examples/sample-report.html) and open it locally for search and collapsible sections. GitHub's file viewer displays its source.*

## Start here

```bash
git clone https://github.com/apakoning/linux-system-inventory.git
cd linux-system-inventory
bash system-inventory.sh --output "$HOME/Inventory"
```

Open `index.html` in the generated directory. It works offline, with no CDN, web server or external JavaScript library. The report directory is retained alongside its optional `.tar.gz` archive.

Run as your regular user. The collector does not execute the reinstall helper, invoke `sudo`, or request firewall-rule authentication. Running the whole script through `sudo` changes the home directory being inspected.

## A report you can explore

- **System overview:** distribution, processor, logical CPUs, physical memory and report coverage.
- **Collection diagnostics:** completed commands, skipped tools and collection errors, with command-level status. These are collection outcomes, not a system-health score.
- **Filesystem capacity:** labeled usage bars from the recorded `df` output.
- **Search:** filter section titles and their complete collected output, then filter by collection status.
- **Collapsible evidence:** expand individual sections or all visible results.
- **Raw files:** text reports, a status TSV and a review-before-use DNF reinstall helper when a clean package query succeeds.

The utility records distribution, kernel, CPU, memory, disks, filesystems, PCI/USB devices, networking, RPM packages, repositories, Flatpak/Snap, language package managers, fonts, GNOME extensions, systemd and security-tool output. It lists shell configuration metadata, not configuration contents.

## Unattended collection

Every collected command runs with standard input closed and a default 30-second timeout (plus a five-second termination grace period). A failure leaves a diagnostic and collection continues. DNF queries use **cached metadata only**, quiet mode, an automatic “no” response and a disabled subscription-manager plugin. Repositories without usable local metadata may produce partial results; the script does not refresh their caches or perform registration.

Firewall rule listing is skipped for non-root users to avoid PolicyKit authentication. Other privileged details may be unavailable. A failed or contaminated package query omits the executable reinstall helper, preserves diagnostics and still allows HTML generation and archiving.

## Render an existing inventory

No need to collect again when you already have text reports:

```bash
bash system-inventory.sh --render-only /path/to/system-inventory-folder
```

The renderer does not query the host. Missing fields are shown as “Not recorded”; older reports without a status log show unknown coverage. Regenerating HTML does not rebuild an existing archive.

## Options

| Option | Purpose |
| --- | --- |
| `-h`, `--help` | Show help |
| `-v`, `--version` | Show version |
| `-o`, `--output DIR` | Parent directory for the new report |
| `--render-only DIR` | Generate HTML from an existing report directory |
| `--command-timeout N` | Maximum seconds per command; default 30 |
| `--appimage-depth N` | AppImage search depth; default 6 |
| `--no-tar` | Omit the archive |
| `-q`, `--quiet` | Suppress progress; retain final paths |

## Requirements and limits

Bash 4+, GNU core utilities including `timeout`, `find`, `tar`, and **Python 3 for HTML generation**. The renderer uses only the Python standard library. Without Python, collection still produces text reports. Optional tools are never installed automatically.

Primary target: RHEL 9 and related systems using DNF 4. Other distributions receive partial coverage; Debian/Ubuntu package inventory and DNF 5 compatibility are not implemented or promised. Python package reports describe the selected `python3` interpreter, not every environment. Filesystem searches have a depth limit.

Reports are snapshots, not backups or restore guarantees. They include network addresses, serial numbers, repository definitions and other machine details. Inspect them for credentials before sharing. The public example contains fictional data and is generated independently of any real inventory.

## Development

```bash
bash -n system-inventory.sh
python3 -m unittest discover -s tests -v
python3 examples/generate-demo.py
```

Regression tests mock collection commands and cover unattended input, timeouts, invalid package output, archive failure, HTML escaping and rendering existing reports. They do not install packages or inventory the test host.

## License

[MIT](LICENSE). Maintained by [Alain A.P. Koningverdraag](https://github.com/apakoning).
