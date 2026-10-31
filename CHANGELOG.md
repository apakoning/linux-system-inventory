# Changelog

## 1.4.0 — 2026-10-30

- Add an offline HTML report with overview cards, storage bars, searchable collapsible sections and visible collection outcomes.
- Render existing inventories without recollecting system data.
- Bound commands with timeouts, close stdin, query cached DNF metadata and skip unprivileged firewall authentication.
- Preserve unexpected DNF output and omit unsafe reinstall helpers without aborting the report.
- Replace the minimal report example with a reproducible fictional HTML demonstration.


## 1.3.0 — 2026-10-30

- Replace shell command strings with direct collector functions and an ordered registry.
- Centralize optional-command handling and record command status and diagnostics.
- Validate reinstall queries and generated package names; omit misleading helpers on failure.
- Preserve reports on archive failure, bound AppImage scans, and clarify Python inventory scope.
- Add regression coverage for failed queries and successful/failed archives.


## 1.2.0 — 2026-10-30

- Consolidated the hardware/network collectors previously present only in Handy-Scripts.
- Documented existing CLI options and RPM/DNF scope; added the MIT license.
- Restricted report permissions, made run directories unique, and checked directory/archive failures.
- Generated a valid reinstall helper even when DNF is unavailable.
- Added examples, regression checks and GitHub Actions.
