#!/usr/bin/env bash
set -uo pipefail
umask 077

VERSION="1.2.0"
CREATE_TAR=1
QUIET=0
BASE_OUTPUT_DIR="$HOME"

usage() {
cat <<EOF
Linux System Inventory $VERSION

Usage:
  ./system-inventory.sh [OPTIONS]

Options:
  --help              Show this help message
  --version           Show version
  -o, --output DIR        Write inventory folder inside DIR
  --no-tar            Do not create compressed .tar.gz archive
  -q, --quiet             Reduce console output

Examples:
  ./system-inventory.sh
  ./system-inventory.sh --output ~/Inventory
  ./system-inventory.sh --no-tar
EOF
}

log() {
    [[ "$QUIET" -eq 0 ]] && echo "$@"
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

run() {
    local name="$1"
    shift

    local file
    file="$(safe_name "$name").txt"

    log "Collecting: $name"

    {
        section "$name"
        "$@" 2>&1 || printf '\nCollection command failed (status %s).\n' "$?"
    } > "$OUT/$file" || { echo "Cannot write report: $file" >&2; exit 1; }
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
        --no-tar)
            CREATE_TAR=0
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            echo
            usage
            exit 1
            ;;
    esac
done

HOST="$(hostname 2>/dev/null || echo unknown-host)"
STAMP="$(date +%F_%H-%M-%S)"
OUT="$BASE_OUTPUT_DIR/system-inventory-${HOST}-${STAMP}"

mkdir -p "$BASE_OUTPUT_DIR" || exit 1
OUT="$(mktemp -d "$OUT-XXXXXX")" || exit 1

log "Linux System Inventory $VERSION"
log "Writing inventory to: $OUT"
log

# Basic system info
run "system-info" bash -c '
echo "--- hostnamectl ---"
hostnamectl 2>/dev/null || true
echo

echo "--- /etc/os-release ---"
cat /etc/os-release 2>/dev/null || true
echo

echo "--- /etc/redhat-release ---"
cat /etc/redhat-release 2>/dev/null || true
echo

echo "--- kernel ---"
uname -a
'

# Hardware
run "cpu-info" bash -c '
lscpu 2>/dev/null || cat /proc/cpuinfo 2>/dev/null || true
'

run "memory-info" bash -c '
free -h 2>/dev/null || true
echo
cat /proc/meminfo 2>/dev/null || true
'

run "block-devices" bash -c '
lsblk -f 2>/dev/null || true
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL 2>/dev/null || true
'

run "pci-devices" bash -c '
lspci 2>/dev/null || true
'

run "usb-devices" bash -c '
lsusb 2>/dev/null || true
'

# Filesystems
run "filesystem-usage" bash -c '
df -hT 2>/dev/null || true
echo
mount 2>/dev/null || true
'

# Networking
run "network-info" bash -c '
ip addr 2>/dev/null || true
echo
ip route 2>/dev/null || true
echo
resolvectl status 2>/dev/null || cat /etc/resolv.conf 2>/dev/null || true
'

run "listening-ports" bash -c '
ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null || true
'

# RPM / DNF
run "rpm-all-packages" bash -c '
have_rpm() { command -v rpm >/dev/null 2>&1; }
have_rpm && rpm -qa --qf "%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n" | sort || true
'

run "rpm-user-installed" bash -c '
command -v dnf >/dev/null 2>&1 && dnf repoquery --userinstalled --qf "%{name} %{evr}.%{arch}" 2>/dev/null | sort || true
'

run "rpm-extras-not-from-enabled-repos" bash -c '
command -v dnf >/dev/null 2>&1 && dnf repoquery --extras --qf "%{name} %{evr}.%{arch}" 2>/dev/null | sort || true
'

run "rpm-third-party-vendors" bash -c '
command -v rpm >/dev/null 2>&1 || exit 0
rpm -qa --qf "%{NAME} | %{VERSION}-%{RELEASE}.%{ARCH} | %{VENDOR}\n" \
| grep -viE "Red Hat|Fedora Project|CentOS|AlmaLinux|Rocky|Oracle" \
| sort || true
'

# Repositories
run "dnf-repos-enabled" bash -c '
command -v dnf >/dev/null 2>&1 && dnf repolist --enabled || true
'

run "dnf-repos-all" bash -c '
command -v dnf >/dev/null 2>&1 && dnf repolist --all || true
'

run "dnf-repo-files" bash -c '
ls -l /etc/yum.repos.d 2>/dev/null || true
echo
cat /etc/yum.repos.d/*.repo 2>/dev/null || true
'

run "dnf-modules" bash -c '
command -v dnf >/dev/null 2>&1 && dnf module list --enabled || true
'

run "dnf-groups" bash -c '
command -v dnf >/dev/null 2>&1 && dnf group list --installed || true
'

# Flatpak / Snap
run "flatpak-apps" bash -c '
command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=application,origin,branch,installation || true
'

run "flatpak-remotes" bash -c '
command -v flatpak >/dev/null 2>&1 && flatpak remotes -d || true
'

run "snap-packages" bash -c '
command -v snap >/dev/null 2>&1 && snap list || true
'

# AppImages / manual installs
run "appimages" bash -c '
find "$HOME" /opt /usr/local -type f -iname "*.AppImage" 2>/dev/null | sort || true
'

run "usr-local" bash -c '
find /usr/local -maxdepth 4 -type f 2>/dev/null | sort || true
'

run "opt-directory" bash -c '
find /opt -maxdepth 4 -type f 2>/dev/null | sort || true
'

run "local-bin" bash -c '
find "$HOME/.local/bin" "$HOME/bin" -type f 2>/dev/null | sort || true
'

# Fonts
run "fonts-system-and-user" bash -c '
fc-list 2>/dev/null | sort || true
echo
echo "--- Font directories ---"
find "$HOME/.local/share/fonts" "$HOME/.fonts" /usr/local/share/fonts /usr/share/fonts \
    -type f 2>/dev/null | sort || true
'

run "nerd-fonts-detected" bash -c '
fc-list 2>/dev/null | grep -i "nerd" | sort || true
find "$HOME/.local/share/fonts" "$HOME/.fonts" /usr/local/share/fonts /usr/share/fonts \
    -type f 2>/dev/null | grep -i "nerd" | sort || true
'

# Language package managers
run "python-pip-user-packages" bash -c '
python3 -m pip list --user 2>/dev/null || true
'

run "python-pip-global-packages" bash -c '
python3 -m pip list 2>/dev/null || true
'

run "npm-global-packages" bash -c '
command -v npm >/dev/null 2>&1 && npm list -g --depth=0 || true
'

run "cargo-installed" bash -c '
command -v cargo >/dev/null 2>&1 && cargo install --list || true
'

run "go-env-and-binaries" bash -c '
command -v go >/dev/null 2>&1 && go env || true
echo
find "$HOME/go/bin" -type f 2>/dev/null | sort || true
'

run "ruby-gems" bash -c '
command -v gem >/dev/null 2>&1 && gem list || true
'

run "perl-local" bash -c '
find "$HOME/perl5" -maxdepth 4 -type f 2>/dev/null | sort || true
'

# Services
run "enabled-systemd-services" bash -c '
systemctl list-unit-files --state=enabled 2>/dev/null || true
'

run "running-systemd-services" bash -c '
systemctl --type=service --state=running 2>/dev/null || true
'

run "failed-systemd-units" bash -c '
systemctl --failed 2>/dev/null || true
'

# Desktop / shell
run "shell-configs" bash -c '
ls -la "$HOME"/.bashrc "$HOME"/.bash_profile "$HOME"/.zshrc "$HOME"/.profile 2>/dev/null || true
'

run "gnome-extensions" bash -c '
command -v gnome-extensions >/dev/null 2>&1 && gnome-extensions list || true
'

run "config-directories" bash -c '
find "$HOME/.config" -maxdepth 2 -type d 2>/dev/null | sort || true
'

# Kernel / NVIDIA
run "kernel-and-drivers" bash -c '
uname -r
echo
rpm -qa 2>/dev/null | grep -Ei "nvidia|akmod|kmod|dkms|kernel|v4l2loopback" | sort || true
'

# Security / firewall
run "firewall-and-selinux" bash -c '
firewall-cmd --state 2>/dev/null || true
echo
firewall-cmd --list-all 2>/dev/null || true
echo
getenforce 2>/dev/null || true
sestatus 2>/dev/null || true
'

# Reinstall helper
log "Creating reinstall helper..."

{
    echo "#!/usr/bin/env bash"
    echo "# Reinstall helper generated on $(date)"
    echo "# Host: $HOST"
    echo
    echo "# Review this before running on a new system."
    echo "# Some package names may change between releases."
    echo
    echo "set -euo pipefail"
    echo 'packages=('


    if have_cmd dnf; then
        dnf repoquery --userinstalled --qf "%{name}" 2>/dev/null \
            | sort -u \
            | sed "s/.*/  '&'/"
    fi
    echo ')'
    echo 'if (( ${#packages[@]} )); then sudo dnf install -- "${packages[@]}"; else echo "No DNF package list available."; fi'
} > "$OUT/reinstall-dnf-userinstalled.sh"

chmod +x "$OUT/reinstall-dnf-userinstalled.sh"

# Summary
{
    echo "Linux System Inventory $VERSION"
    echo "Generated: $(date)"
    echo "Host: $HOST"
    echo "Output directory: $OUT"
    echo
    echo "Files generated:"
    find "$OUT" -maxdepth 1 -type f -printf "%f\n" | sort
} > "$OUT/summary.txt"

# Archive
if [[ "$CREATE_TAR" -eq 1 ]]; then
    log "Creating archive..."
    tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")" || { echo "Archive creation failed." >&2; exit 1; }
fi

echo
echo "Done."
echo "Inventory folder:"
echo "$OUT"

if [[ "$CREATE_TAR" -eq 1 ]]; then
    echo
    echo "Compressed archive:"
    echo "$OUT.tar.gz"
fi

