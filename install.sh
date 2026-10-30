#!/usr/bin/env bash
#
# Umbriel + Noctalia + Noctalia Greeter desktop for a minimal Arch install.
#
# Target hardware: AMD Ryzen 7 9800X3D (Zen 5) + Radeon RX 9070 XT (RDNA 4).
#
# Installs:
#   - AMD microcode, firmware and the Mesa/RADV graphics stack (incl. 32-bit for Steam/Proton)
#   - Umbriel (Wayland compositor) + xdg-desktop-portal-umbriel
#   - Noctalia v5 (desktop shell), autostarted by Umbriel
#   - Noctalia Greeter on greetd (login screen)
#   - Kitty, Helium browser, Nautilus
#
# Run from the TTY as your normal user (NOT root), with sudo rights:
#   ./install.sh
#
# Options (environment variables):
#   AUR_HELPER=yay|paru   AUR helper to use/bootstrap (default: yay)
#   ENABLE_MULTILIB=0     skip enabling [multilib] and the 32-bit GPU drivers
#   ENABLE_GREETER=0      install everything but don't switch login to greetd

set -euo pipefail

AUR_HELPER="${AUR_HELPER:-yay}"
ENABLE_MULTILIB="${ENABLE_MULTILIB:-1}"
ENABLE_GREETER="${ENABLE_GREETER:-1}"

# ------------------------------------------------------------------------------
# Helpers

info() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

pacman_install() {
    sudo pacman -S --needed --noconfirm "$@"
}

# Install the first package name that exists, preferring the official repos
# over the AUR. Some of these projects are moving from the AUR into [extra],
# so the exact name/location differs depending on when this is run.
install_first_available() {
    local label="$1"; shift
    local pkg
    for pkg in "$@"; do
        if pacman -Si "$pkg" &>/dev/null; then
            info "Installing $label from the official repos ($pkg)"
            pacman_install "$pkg"
            return 0
        fi
    done
    for pkg in "$@"; do
        if "$AUR_HELPER" -Si --aur "$pkg" &>/dev/null; then
            info "Installing $label from the AUR ($pkg)"
            "$AUR_HELPER" -S --needed --noconfirm "$pkg"
            return 0
        fi
    done
    return 1
}

# ------------------------------------------------------------------------------
# Pre-flight checks

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not root (makepkg refuses to run as root)."
command -v sudo &>/dev/null || die "sudo is not installed. As root: pacman -S sudo && EDITOR=nano visudo (enable %wheel)."
command -v git  &>/dev/null || die "git is not installed."
[[ -f /etc/arch-release ]]  || die "This script is for Arch Linux."
case "$AUR_HELPER" in yay|paru) ;; *) die "AUR_HELPER must be 'yay' or 'paru'." ;; esac

info "Checking sudo access"
sudo -v || die "Your user needs sudo rights."
# Keep the sudo timestamp fresh for the duration of the (long) AUR builds.
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

info "Checking internet connection"
ping -c 1 -W 5 archlinux.org &>/dev/null || die "No internet connection. Connect first (nmtui / iwctl) and re-run."

# ------------------------------------------------------------------------------
# pacman setup

info "Tuning pacman (parallel downloads, colour)"
sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^#Color$/Color/' /etc/pacman.conf

if [[ "$ENABLE_MULTILIB" == 1 ]] && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    info "Enabling [multilib] (32-bit Vulkan/OpenGL for Steam and Proton)"
    sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
fi

info "Updating the system"
sudo pacman -Syu --noconfirm

# ------------------------------------------------------------------------------
# Base tooling

info "Installing build tools"
pacman_install base-devel git

# ------------------------------------------------------------------------------
# CPU: Ryzen 7 9800X3D
#
# amd-ucode: microcode updates (mkinitcpio's `microcode` hook embeds it in the
# initramfs). amd_pstate (active/EPP mode) is the kernel default on Zen 5, and
# power-profiles-daemon drives its energy-performance preference from
# Noctalia's power profile switcher. The 9800X3D has a single CCD, so no
# X3D V-Cache scheduler tweaks are needed.

info "Installing CPU support (microcode, power profiles)"
pacman_install amd-ucode power-profiles-daemon upower

# ------------------------------------------------------------------------------
# GPU: Radeon RX 9070 XT (RDNA 4 / Navi 48)
#
# RDNA 4 needs kernel 6.13+, Mesa 25.0+ and recent linux-firmware, all of which
# current Arch provides. Use the in-kernel amdgpu driver + Mesa (RADV for
# Vulkan). Do NOT install amdvlk or xf86-video-amdgpu (X11-only, not needed on
# Wayland). VA-API video decode (radeonsi) ships inside the mesa package now.

info "Installing AMD graphics stack (Mesa, RADV Vulkan, firmware)"
pacman_install linux-firmware mesa vulkan-radeon vulkan-icd-loader \
    vulkan-tools mesa-utils libva-utils

if grep -q '^\[multilib\]' /etc/pacman.conf; then
    pacman_install lib32-mesa lib32-vulkan-radeon lib32-vulkan-icd-loader
fi

# ------------------------------------------------------------------------------
# Session plumbing: audio, portals, polkit, keyring, fonts

info "Installing audio (PipeWire), portals, polkit, keyring and fonts"
pacman_install \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    sound-theme-freedesktop \
    xorg-xwayland \
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs xdg-utils \
    polkit gnome-keyring libsecret \
    libheif \
    noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd

# ------------------------------------------------------------------------------
# Applications from the official repos

info "Installing Kitty and Nautilus"
pacman_install kitty nautilus gvfs gvfs-mtp ffmpegthumbnailer

# ------------------------------------------------------------------------------
# AUR helper

if ! command -v "$AUR_HELPER" &>/dev/null; then
    info "Bootstrapping AUR helper: $AUR_HELPER"
    build_dir="$(mktemp -d)"
    git clone --depth 1 "https://aur.archlinux.org/${AUR_HELPER}-bin.git" "$build_dir/${AUR_HELPER}-bin"
    (cd "$build_dir/${AUR_HELPER}-bin" && makepkg -si --noconfirm)
    rm -rf "$build_dir"
fi

# ------------------------------------------------------------------------------
# Umbriel, Noctalia, Noctalia Greeter, Helium

# Umbriel is built from source (C++23 / wlroots 0.20); this takes a few minutes.
install_first_available "Umbriel" umbriel umbriel-git \
    || die "Could not find an Umbriel package (tried: umbriel, umbriel-git)."

install_first_available "xdg-desktop-portal-umbriel (screen sharing)" \
    xdg-desktop-portal-umbriel xdg-desktop-portal-umbriel-git \
    || warn "xdg-desktop-portal-umbriel not found; screen sharing will not work until it is installed."

install_first_available "Noctalia" noctalia noctalia-git \
    || die "Could not find a Noctalia package (tried: noctalia, noctalia-git)."

install_first_available "Noctalia Greeter" noctalia-greeter noctalia-greeter-git \
    || die "Could not find a Noctalia Greeter package (tried: noctalia-greeter, noctalia-greeter-git)."

install_first_available "Helium browser" helium-browser-bin \
    || die "Could not find helium-browser-bin in the AUR."

# ------------------------------------------------------------------------------
# User configuration

info "Creating XDG user directories"
xdg-user-dirs-update

UMBRIEL_CONFIG="$HOME/.config/umbriel/config.toml"
if [[ -f "$UMBRIEL_CONFIG" ]]; then
    warn "$UMBRIEL_CONFIG already exists; leaving it alone. Make sure [general] has: autostart = [\"noctalia\"]"
else
    info "Writing Umbriel config (autostarts Noctalia)"
    mkdir -p "$(dirname "$UMBRIEL_CONFIG")"
    umbriel_default=/usr/share/umbriel/config.toml
    if [[ -f "$umbriel_default" ]]; then
        cp "$umbriel_default" "$UMBRIEL_CONFIG"
        # The packaged config has a [general] table with autostart commented out.
        sed -i '0,/^\[general\]/ s//[general]\nautostart = ["noctalia"]/' "$UMBRIEL_CONFIG"
    else
        printf '[general]\nautostart = ["noctalia"]\n' > "$UMBRIEL_CONFIG"
    fi
    grep -q '^autostart = \["noctalia"\]' "$UMBRIEL_CONFIG" \
        || warn "Could not add the Noctalia autostart line; add autostart = [\"noctalia\"] under [general] in $UMBRIEL_CONFIG"
fi

# Default applications
xdg-mime default org.gnome.Nautilus.desktop inode/directory || true
helium_desktop="$(pacman -Qlq helium-browser-bin 2>/dev/null | grep '/share/applications/.*\.desktop$' | head -n1 || true)"
if [[ -n "$helium_desktop" ]]; then
    xdg-settings set default-web-browser "$(basename "$helium_desktop")" || true
fi

# ------------------------------------------------------------------------------
# Services

info "Enabling system services"
sudo systemctl enable power-profiles-daemon.service

# Rebuild initramfs so amd-ucode and the latest amdgpu firmware are picked up.
info "Regenerating initramfs"
sudo mkinitcpio -P

# ------------------------------------------------------------------------------
# Login: greetd + Noctalia Greeter

if [[ "$ENABLE_GREETER" == 1 ]]; then
    info "Configuring greetd to launch Noctalia Greeter"
    pacman_install greetd

    getent passwd greeter &>/dev/null || sudo systemd-sysusers
    getent passwd greeter &>/dev/null || die "The 'greeter' user was not created by the greetd package."

    session_bin="$(command -v noctalia-greeter-session || true)"
    [[ -n "$session_bin" ]] || die "noctalia-greeter-session not found on PATH."

    if [[ -f /etc/greetd/config.toml ]]; then
        sudo cp /etc/greetd/config.toml "/etc/greetd/config.toml.bak.$(date +%Y%m%d%H%M%S)"
    fi
    sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "$session_bin"
user = "greeter"
EOF

    # Greeter state directory (/var/lib/noctalia-greeter) + greeter.toml/sync.toml
    sudo systemd-tmpfiles --create noctalia-greeter.conf 2>/dev/null || true
    if command -v noctalia-greeter-apply-appearance &>/dev/null; then
        sudo noctalia-greeter-apply-appearance --setup-system
    fi

    # Make Umbriel the session the greeter preselects.
    greeter_toml=/var/lib/noctalia-greeter/greeter.toml
    if [[ -f /usr/share/wayland-sessions/umbriel.desktop ]] && sudo test -f "$greeter_toml" \
        && ! sudo grep -q '^\[session\]' "$greeter_toml"; then
        umbriel_name="$(sed -n 's/^Name=//p' /usr/share/wayland-sessions/umbriel.desktop | head -n1)"
        printf '\n[session]\ndefault = "%s"\n' "${umbriel_name:-Umbriel}" | sudo tee -a "$greeter_toml" >/dev/null
    fi

    # Disable any other display manager, then enable greetd (takes effect on reboot).
    current_dm="$(systemctl show -p Id --value display-manager.service 2>/dev/null || true)"
    if [[ -n "$current_dm" && "$current_dm" != "display-manager.service" && "$current_dm" != "greetd.service" ]]; then
        info "Disabling existing display manager: $current_dm"
        sudo systemctl disable "$current_dm"
    fi
    sudo systemctl enable greetd.service
else
    warn "Skipping greetd setup. Start the desktop from the TTY with: start-umbriel"
fi

# ------------------------------------------------------------------------------

info "Done!"
cat <<'EOF'

  Reboot to land on the Noctalia Greeter and pick the Umbriel session:

      sudo reboot

  Default keys in Umbriel:
      Super            Noctalia launcher
      Super+Return     Kitty
      Super+Q          Close window
      Super+Escape     Quit session

  Useful after first login:
      umbriel outputs                  list monitors / modes
      ~/.config/umbriel/config.toml    compositor config (live reload)
      vulkaninfo --summary             should show "AMD Radeon RX 9070 XT (RADV GFX1201)"

  For high refresh rate / VRR, add to ~/.config/umbriel/config.toml, e.g.:
      [output.DP-1]
      mode = "2560x1440@165"
      vrr = "fullscreen"

  If the greeter fails to start, switch to another TTY (Ctrl+Alt+F2), log in and run:
      journalctl -b -u greetd
      sudo systemctl disable greetd   # falls back to TTY login; then use start-umbriel
EOF
