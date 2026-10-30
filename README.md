# arch-umbriel-noctalia
This is a custom build of Arch Linux with Umbriel compositor and Noctalia shell

## Usage

1. Install Arch with `archinstall`: **Minimal** profile, a user with sudo
   (wheel) rights, a network setup (e.g. NetworkManager), and PipeWire audio
   if you like (the script installs it anyway).
2. Reboot, log in on the TTY as your user, then:

```bash
git clone https://github.com/lmaule/arch-umbriel-noctalia.git
cd arch-umbriel-noctalia
./install.sh
sudo reboot
```

The script is tuned for a Ryzen 7 9800X3D + Radeon RX 9070 XT (amd-ucode,
Mesa/RADV, 32-bit Vulkan via `[multilib]`) and installs:

- Umbriel compositor (+ `xdg-desktop-portal-umbriel` for screen sharing)
- Noctalia shell, autostarted from `~/.config/umbriel/config.toml`
- Noctalia Greeter on greetd
- Kitty, Helium browser (AUR `helium-browser-bin`), Nautilus

Options: `AUR_HELPER=paru`, `ENABLE_MULTILIB=0`, `ENABLE_GREETER=0`
(e.g. `ENABLE_GREETER=0 ./install.sh`, then start from a TTY with `start-umbriel`).

Everything the script prints is also saved to `~/umbriel-install.log`. The
script is safe to re-run; if Umbriel can't be installed from a package, it
falls back to building it from upstream source with Meson.
