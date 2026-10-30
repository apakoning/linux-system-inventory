# Linux System Inventory

[![Checks](https://github.com/apakoning/linux-system-inventory/actions/workflows/checks.yml/badge.svg)](https://github.com/apakoning/linux-system-inventory/actions/workflows/checks.yml)

A Bash utility that collects hardware, software, networking and service information into a private local report directory, with an optional compressed archive. Built for system documentation, support and migration preparation.

## Quick start

```bash
git clone https://github.com/apakoning/linux-system-inventory.git
cd linux-system-inventory
bash system-inventory.sh --output "$HOME/Inventory"
```

Run as your regular user to inventory your own applications and configuration paths. Some privileged information may be unavailable; running the whole script through `sudo` changes which home directory is inspected.

## Collected information

- Distribution, kernel, CPU, memory, disks, filesystems, PCI and USB devices.
- Interfaces, routes, DNS configuration and listening ports.
- RPM packages, DNF repositories, modules and package groups.
- Flatpak, Snap, AppImages and available language package managers.
- Enabled, running and failed systemd services; firewall and SELinux status.
- Fonts, GNOME extension names and local installation/configuration paths.
- A review-before-use DNF package reinstall helper.

The script lists shell configuration metadata; it does not copy shell configuration contents. Repository definitions are included, so review reports for embedded credentials and internal hostnames before sharing them.

## Requirements and scope

Bash 4+, GNU core utilities, `find` and `tar`. The main target is RHEL 9 and related RPM/DNF systems. Hardware details use optional commands such as `lspci` and `lsusb`. Unavailable optional tools and failed commands are recorded in `collection-status.tsv`; the utility does not install packages.

It can collect partial information elsewhere, but Debian/Ubuntu package inventory is **not implemented**. Compatibility with every listed tool and distribution is not implied by the automated smoke checks.

## Options

```text
-h, --help        Show help
-v, --version     Show version
-o, --output DIR  Parent directory for the generated report
--appimage-depth N  AppImage search maximum depth (default: 6)
--no-tar          Skip the .tar.gz archive
-q, --quiet       Suppress collection progress; retain final output paths
```

```bash
bash system-inventory.sh --no-tar --quiet --output /tmp/inventory
```

## Output

Each run creates a unique directory with restrictive permissions:

```text
system-inventory-example-host-2026-10-30_12-00-00-ABC123/
  collection-status.tsv
  summary.txt
  system-info.txt
  cpu-info.txt
  memory-info.txt
  network-info.txt
  rpm-all-packages.txt
  reinstall-dnf-userinstalled.sh
  ...
```

See [examples/sample-report.md](examples/sample-report.md) for an illustrative report excerpt. Reports are snapshots, not a backup or a restore guarantee. DNF metadata queries can contact enabled repositories and refresh local metadata. A failed reinstall query omits the executable helper and creates an explanatory status file.

The report directory is retained after archiving, including when archive creation fails. Quiet mode still prints final output paths. AppImage searches are limited to six directory levels by default; use `--appimage-depth N` to adjust this. Python reports cover the selected `python3` interpreter, not all installed interpreters or virtual environments.

## Development

```bash
bash -n system-inventory.sh
python3 -m unittest discover -s tests -v
```

The regression checks mock system commands; they never inventory the CI host or install packages.

## License

[MIT](LICENSE). Maintained by [Alain A.P. Koningverdraag](https://github.com/apakoning).
