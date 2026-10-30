#!/usr/bin/env bash
set -uo pipefail
umask 077

VERSION="1.3.0"
CREATE_TAR=1
QUIET=0
BASE_OUTPUT_DIR="$HOME"
APPIMAGE_DEPTH=6

usage() {
cat <<EOF
Linux System Inventory $VERSION

Usage:
  ./system-inventory.sh [OPTIONS]

Options:
  --help              Show this help message
  --version           Show version
  -o, --output DIR        Write inventory folder inside DIR
  --appimage-depth N  AppImage search depth (default: 6)
  --no-tar            Do not create compressed .tar.gz archive
  -q, --quiet             Reduce console output

Examples:
  ./system-inventory.sh
  ./system-inventory.sh --output ~/Inventory
  ./system-inventory.sh --no-tar
EOF
}

log() {
    if [[ "$QUIET" -eq 0 ]]; then printf '%s\n' "$*"; fi
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

safe_name() {
    echo "$1" | tr ' /' '--' | tr -cd '[:alnum:]_.-'
}

section() {
    echo
    echo "==== $1 ===="
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Commands are passed as argument arrays, never interpreted with eval.
# Diagnostics stay in the report; status records survive pipelines/subshells.
capture() {
    local status=0
    printf '\n---'; printf ' %q' "$@"; printf ' ---\n'
    if ! have_cmd "$1"; then
        printf 'SKIPPED: command unavailable: %s\n' "$1"
        printf '%s\tSKIPPED\t%s\n' "$REPORT" "$1" >> "$STATUS_FILE" || die "Cannot write status log"
        return 0
    fi
    "$@" || status=$?
    if (( status )); then
        printf '\nFAILED: exit status %s\n' "$status"
        printf '%s\tFAILED:%s\t%s\n' "$REPORT" "$status" "$1" >> "$STATUS_FILE" || die "Cannot write status log"
    else
        printf '%s\tOK\t%s\n' "$REPORT" "$1" >> "$STATUS_FILE" || die "Cannot write status log"
    fi
    return 0
}

report() {
    REPORT="$1"
    shift
    log "Collecting: $REPORT"
    { section "$REPORT"; "$@"; } > "$OUT/$REPORT.txt" 2>&1 || die "Cannot write report: $REPORT"
}

# Shared filesystem collector: skip absent paths explicitly, retain find errors.
files() {
    local depth="$1" path
    shift
    for path in "$@"; do
        if [[ -e "$path" ]]; then
            capture find "$path" -maxdepth "$depth" -type f
        else
            printf 'Absent path: %s\n' "$path"
        fi
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --version|-v)
            echo "Linux System Inventory $VERSION"
            exit 0
            ;;
        --output|-o)
            if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                echo "ERROR: --output requires a directory." >&2
                exit 2
            fi
            BASE_OUTPUT_DIR="$2"
            shift 2
            ;;
        --appimage-depth)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die "--appimage-depth requires a nonnegative integer"
            APPIMAGE_DEPTH="$2"
            shift 2
            ;;
        --no-tar)
            CREATE_TAR=0
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo
            usage
            exit 1
            ;;
    esac
done

HOST="$(safe_name "$(hostname 2>/dev/null || printf unknown-host)")"
HOST="${HOST:-unknown-host}"
STAMP="$(date +%F_%H-%M-%S)" || die "Cannot read date"
mkdir -p -- "$BASE_OUTPUT_DIR" || die "Cannot create output directory"
BASE_OUTPUT_DIR="$(cd -- "$BASE_OUTPUT_DIR" && pwd -P)" || die "Cannot resolve output directory"
OUT="$(mktemp -d "$BASE_OUTPUT_DIR/system-inventory-$HOST-$STAMP-XXXXXX")" || die "Cannot create report directory"
STATUS_FILE="$OUT/collection-status.tsv"
printf 'section\tstatus\tcommand\n' > "$STATUS_FILE" || die "Cannot create status log"
export SYSTEMD_PAGER=cat PAGER=cat
log "Linux System Inventory $VERSION"
log "Writing inventory to: $OUT"
if (( EUID == 0 )); then
    printf 'NOTICE: Running as root; user paths refer to %s. Run as your regular user for your personal inventory.\n' "$HOME" >&2
fi

collect_system_info() {
    echo "--- hostnamectl ---"; capture hostnamectl; echo; echo "--- /etc/os-release ---"; capture cat /etc/os-release; echo; echo "--- /etc/redhat-release ---"; capture cat /etc/redhat-release; echo; echo "--- kernel ---"; capture uname -a
}

collect_cpu_info() {
    if have_cmd lscpu; then capture lscpu; else capture cat /proc/cpuinfo; fi
}

collect_memory_info() {
    capture free -h; echo; capture cat /proc/meminfo
}

collect_block_devices() {
    capture lsblk -f; echo; capture lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL
}

collect_pci_devices() {
    capture lspci
}

collect_usb_devices() {
    capture lsusb
}

collect_filesystem_usage() {
    capture df -hT; echo; capture mount
}

collect_network_info() {
    capture ip addr; echo; capture ip route; echo; if have_cmd resolvectl; then capture resolvectl status; else capture cat /etc/resolv.conf; fi
}

collect_listening_ports() {
    if have_cmd ss; then capture ss -tulpn; else capture netstat -tulpn; fi
}

collect_rpm_all_packages() {
    capture rpm -qa --qf "%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n" | sort
}

collect_rpm_user_installed() {
    capture dnf repoquery --userinstalled --qf "%{name} %{evr}.%{arch}" | sort
}

collect_rpm_extras_not_from_enabled_repos() {
    capture dnf repoquery --extras --qf "%{name} %{evr}.%{arch}" | sort
}

collect_rpm_third_party_vendors() {
    capture rpm -qa --qf "%{NAME} | %{VERSION}-%{RELEASE}.%{ARCH} | %{VENDOR}\n" | awk 'BEGIN { IGNORECASE=1 } !/Red Hat|Fedora Project|CentOS|AlmaLinux|Rocky|Oracle/'  | sort
}

collect_dnf_repos_enabled() {
    capture dnf repolist --enabled
}

collect_dnf_repos_all() {
    capture dnf repolist --all
}

collect_dnf_repo_files() {
    capture ls -l /etc/yum.repos.d; echo; capture cat /etc/yum.repos.d/*.repo
}

collect_dnf_modules() {
    capture dnf module list --enabled
}

collect_dnf_groups() {
    capture dnf group list --installed
}

collect_flatpak_apps() {
    capture flatpak list --app --columns=application,origin,branch,installation
}

collect_flatpak_remotes() {
    capture flatpak remotes -d
}

collect_snap_packages() {
    capture snap list
}

collect_appimages() {
    capture find "$HOME" /opt /usr/local -maxdepth "$APPIMAGE_DEPTH" -type f -iname "*.AppImage" | sort
}

collect_usr_local() {
    files 4 /usr/local | sort
}

collect_opt_directory() {
    files 4 /opt | sort
}

collect_local_bin() {
    files 4 "$HOME/.local/bin" "$HOME/bin" | sort
}

collect_fonts_system_and_user() {
    capture fc-list | sort; echo; echo "--- Font directories ---"; capture find "$HOME/.local/share/fonts" "$HOME/.fonts" /usr/local/share/fonts /usr/share/fonts -type f | sort
}

collect_nerd_fonts_detected() {
    capture fc-list | awk 'tolower($0) ~ /nerd/' | sort; capture find "$HOME/.local/share/fonts" "$HOME/.fonts" /usr/local/share/fonts /usr/share/fonts -type f | awk 'tolower($0) ~ /nerd/' | sort
}

collect_python_pip_user_packages() {
    capture python3 -m pip list --user
}

collect_python_pip_visible_packages() {
    capture python3 -m pip list
}

collect_npm_global_packages() {
    capture npm list -g --depth=0
}

collect_cargo_installed() {
    capture cargo install --list
}

collect_go_env_and_binaries() {
    capture go env; echo; capture find "$HOME/go/bin" -type f | sort
}

collect_ruby_gems() {
    capture gem list
}

collect_perl_local() {
    files 4 "$HOME/perl5" | sort
}

collect_enabled_systemd_services() {
    capture systemctl list-unit-files --state=enabled
}

collect_running_systemd_services() {
    capture systemctl --type=service --state=running
}

collect_failed_systemd_units() {
    capture systemctl --failed
}

collect_shell_configs() {
    capture ls -la "$HOME"/.bashrc "$HOME"/.bash_profile "$HOME"/.zshrc "$HOME"/.profile
}

collect_gnome_extensions() {
    capture gnome-extensions list
}

collect_config_directories() {
    capture find "$HOME/.config" -maxdepth 2 -type d | sort
}

collect_kernel_and_drivers() {
    capture uname -r; echo; capture rpm -qa | awk 'tolower($0) ~ /nvidia|akmod|kmod|dkms|kernel|v4l2loopback/' | sort
}

collect_firewall_and_selinux() {
    capture firewall-cmd --state; echo; capture firewall-cmd --list-all; echo; capture getenforce; capture sestatus
}

# Ordered registry keeps dispatch separate from collector implementation.
COLLECTORS=(
    "system-info"
    "cpu-info"
    "memory-info"
    "block-devices"
    "pci-devices"
    "usb-devices"
    "filesystem-usage"
    "network-info"
    "listening-ports"
    "rpm-all-packages"
    "rpm-user-installed"
    "rpm-extras-not-from-enabled-repos"
    "rpm-third-party-vendors"
    "dnf-repos-enabled"
    "dnf-repos-all"
    "dnf-repo-files"
    "dnf-modules"
    "dnf-groups"
    "flatpak-apps"
    "flatpak-remotes"
    "snap-packages"
    "appimages"
    "usr-local"
    "opt-directory"
    "local-bin"
    "fonts-system-and-user"
    "nerd-fonts-detected"
    "python-pip-user-packages"
    "python-pip-visible-packages"
    "npm-global-packages"
    "cargo-installed"
    "go-env-and-binaries"
    "ruby-gems"
    "perl-local"
    "enabled-systemd-services"
    "running-systemd-services"
    "failed-systemd-units"
    "shell-configs"
    "gnome-extensions"
    "config-directories"
    "kernel-and-drivers"
    "firewall-and-selinux"
 )
for name in "${COLLECTORS[@]}"; do
    report "$name" "collect_${name//-/_}"
done

# A failed query must never yield an apparently valid, empty reinstall script.
REPORT=reinstall-helper
package_file="$OUT/dnf-user-package-names.txt"
if have_cmd dnf; then
    if dnf repoquery --userinstalled --qf '%{name}' > "$package_file" 2> "$OUT/reinstall-query-errors.txt"; then
        sort -u "$package_file" -o "$package_file" || die "Cannot sort package list"
        packages=()
        while IFS= read -r package; do
            [[ -z "$package" ]] && continue
            [[ "$package" =~ ^[[:alnum:]][[:alnum:]+_.-]*$ ]] || die "Unexpected package name in DNF output; reports retained at $OUT"
            packages+=("$package")
        done < "$package_file"
        helper="$OUT/reinstall-dnf-userinstalled.sh"
        {
            printf '#!/usr/bin/env bash\n# Review repositories and package names before running.\nset -euo pipefail\npackages=(\n'
            if (( ${#packages[@]} )); then printf '  %q\n' "${packages[@]}"; fi
            printf ')\nif (( ${#packages[@]} )); then\n    sudo dnf install -- "${packages[@]}"\nelse\n    echo "No user-installed packages recorded."\nfi\n'
        } > "$helper" || die "Cannot write reinstall helper"
        chmod 700 "$helper" || die "Cannot make reinstall helper executable"
    else
        printf 'Reinstall helper omitted: DNF query failed. See reinstall-query-errors.txt.\n' > "$OUT/reinstall-helper-unavailable.txt" || die "Cannot write helper status"
        printf 'reinstall-helper\tFAILED\tdnf repoquery\n' >> "$STATUS_FILE" || die "Cannot write status"
        rm -f -- "$package_file" || die "Cannot remove incomplete package list"
    fi
else
    printf 'Reinstall helper omitted: dnf unavailable.\n' > "$OUT/reinstall-helper-unavailable.txt" || die "Cannot write helper status"
    printf 'reinstall-helper\tSKIPPED\tdnf\n' >> "$STATUS_FILE" || die "Cannot write status"
fi

{
    printf 'Linux System Inventory %s\nHost: %s\nOutput directory: %s\n' "$VERSION" "$HOST" "$OUT"
    printf 'Inspect collection-status.tsv for skipped or failed commands.\n'
    printf 'Reports are an inventory, not a backup. Shell configuration contents are not copied.\n'
    printf 'AppImage search maximum depth: %s\n' "$APPIMAGE_DEPTH"
} > "$OUT/summary.txt" || die "Cannot write summary"

if (( CREATE_TAR )); then
    log "Creating archive..."
    if ! tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"; then
        die "Archive creation failed; reports retained at $OUT (archive may be incomplete)"
    fi
fi
printf '\nDone. Inventory folder: %s\n' "$OUT"
if (( CREATE_TAR )); then printf 'Compressed archive: %s.tar.gz\n' "$OUT"; fi
