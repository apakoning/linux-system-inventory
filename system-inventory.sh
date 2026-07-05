#!/usr/bin/env bash
set -euo pipefail

OUT="$HOME/system-inventory-$(hostname)-$(date +%F_%H-%M-%S)"
mkdir -p "$OUT"

echo "Writing inventory to: $OUT"

section() {
    echo
    echo "==== $1 ===="
}

run() {
    local name="$1"
    shift
    {
        section "$name"
        "$@" 2>&1 || true
    } > "$OUT/$name.txt"
}

# Basic system info
run "system-info" bash -c '
hostnamectl
echo
cat /etc/redhat-release 2>/dev/null
echo
uname -a
'

# RPM packages
run "rpm-all-packages" rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}.%{ARCH}\n'

run "rpm-user-installed" bash -c '
dnf repoquery --userinstalled --qf "%{name} %{evr}.%{arch}" 2>/dev/null || true
'

run "rpm-extras-not-from-enabled-repos" bash -c '
dnf repoquery --extras --qf "%{name} %{evr}.%{arch}" 2>/dev/null || true
'

run "rpm-third-party-vendors" bash -c '
rpm -qa --qf "%{NAME} | %{VERSION}-%{RELEASE}.%{ARCH} | %{VENDOR}\n" \
| grep -viE "Red Hat|Fedora Project|CentOS|AlmaLinux|Rocky|Oracle" \
| sort
'

# Repositories
run "dnf-repos-enabled" dnf repolist --enabled
run "dnf-repos-all" dnf repolist --all
run "dnf-repo-files" bash -c 'ls -l /etc/yum.repos.d && echo && cat /etc/yum.repos.d/*.repo 2>/dev/null'

# Modules / groups
run "dnf-modules" dnf module list --enabled
run "dnf-groups" dnf group list --installed

# Flatpak
run "flatpak-apps" bash -c '
flatpak list --app --columns=application,origin,branch,installation 2>/dev/null || true
'
run "flatpak-remotes" bash -c '
flatpak remotes -d 2>/dev/null || true
'

# Snap, if present
run "snap-packages" bash -c '
command -v snap >/dev/null && snap list || true
'

# AppImages and manually downloaded apps
run "appimages" bash -c '
find "$HOME" /opt /usr/local -type f -iname "*.AppImage" 2>/dev/null | sort
'

# Fonts, including nerd fonts
run "fonts-system-and-user" bash -c '
fc-list 2>/dev/null | sort || true
echo
echo "--- Font directories ---"
find "$HOME/.local/share/fonts" "$HOME/.fonts" /usr/local/share/fonts /usr/share/fonts \
    -type f 2>/dev/null | sort
'

run "nerd-fonts-detected" bash -c '
fc-list 2>/dev/null | grep -i "nerd" | sort || true
find "$HOME/.local/share/fonts" "$HOME/.fonts" /usr/local/share/fonts /usr/share/fonts \
    -type f 2>/dev/null | grep -i "nerd" | sort || true
'

# User binaries and local installs
run "usr-local" bash -c '
find /usr/local -maxdepth 4 -type f 2>/dev/null | sort
'

run "opt-directory" bash -c '
find /opt -maxdepth 4 -type f 2>/dev/null | sort
'

run "local-bin" bash -c '
find "$HOME/.local/bin" "$HOME/bin" -type f 2>/dev/null | sort
'

# Python packages
run "python-pip-user-packages" bash -c '
python3 -m pip list --user 2>/dev/null || true
'

run "python-pip-global-packages" bash -c '
python3 -m pip list 2>/dev/null || true
'

# Node / npm
run "npm-global-packages" bash -c '
command -v npm >/dev/null && npm list -g --depth=0 || true
'

# Rust / Cargo
run "cargo-installed" bash -c '
command -v cargo >/dev/null && cargo install --list || true
'

# Go
run "go-env-and-binaries" bash -c '
command -v go >/dev/null && go env || true
echo
find "$HOME/go/bin" -type f 2>/dev/null | sort
'

# Ruby gems
run "ruby-gems" bash -c '
command -v gem >/dev/null && gem list || true
'

# Perl local libs
run "perl-local" bash -c '
command -v cpanm >/dev/null && cpanm --self-contained 2>/dev/null || true
find "$HOME/perl5" -maxdepth 4 -type f 2>/dev/null | sort
'

# System services
run "enabled-systemd-services" bash -c '
systemctl list-unit-files --state=enabled
'

run "running-systemd-services" bash -c '
systemctl --type=service --state=running
'

# Shells and desktop extensions
run "shell-configs" bash -c '
ls -la "$HOME"/.bashrc "$HOME"/.bash_profile "$HOME"/.zshrc "$HOME"/.profile 2>/dev/null || true
'

run "gnome-extensions" bash -c '
command -v gnome-extensions >/dev/null && gnome-extensions list || true
'

# Important config directories
run "config-directories" bash -c '
find "$HOME/.config" -maxdepth 2 -type d 2>/dev/null | sort
'

# NVIDIA / kernel-related extras
run "kernel-and-drivers" bash -c '
uname -r
echo
rpm -qa | grep -Ei "nvidia|akmod|kmod|dkms|kernel|v4l2loopback" | sort
'

# Create a reinstall helper list
{
    echo "# Reinstall helper generated on $(date)"
    echo
    echo "# Review this before running on RHEL 10."
    echo "# Some package names may change."
    echo
    echo "sudo dnf install \\"
    dnf repoquery --userinstalled --qf "%{name}" 2>/dev/null \
        | sort -u \
        | sed 's/$/ \\/'
} > "$OUT/reinstall-dnf-userinstalled.sh"

chmod +x "$OUT/reinstall-dnf-userinstalled.sh"

# Create archive
tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"

echo
echo "Done."
echo "Inventory folder:"
echo "$OUT"
echo
echo "Compressed archive:"
echo "$OUT.tar.gz"
