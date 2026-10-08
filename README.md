# xiaomi-book-pro.nix

[English](README.md) | [简体中文](README.zh-CN.md)

NixOS hardware support for **Xiaomi Book Pro 14 (2026), board TM2424**.

This flake provides hardware fixes without changing your desktop, disk layout,
bootloader or choice of kernel. Replacement drivers are built as individual
modules; a full kernel rebuild is not required.

## Quick start

Add the input to your flake:

```nix
inputs.xiaomi-book-pro = {
  url = "github:ManiaciaChao/xiaomi-book-pro.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then add this to your NixOS configuration, with `inputs` available where you
declare the import:

```nix
imports = [ inputs.xiaomi-book-pro.nixosModules.tm2424 ];
hardware.xiaomi-book-pro.enable = true;
```

Rebuild your NixOS configuration and reboot to load the kernel changes.
`nixosModules.default` is an alias for `tm2424`.

## What's included

All feature groups below are enabled by default when you enable the profile.

| Feature | Support |
| --- | --- |
| Keyboard | Paired `i8042.nopnp` / `i8042.dumbkbd` workaround on Linux < 7.2 |
| Graphics | GPU `b080` force-probe on Linux < 6.17; OLED PSR workaround |
| Fingerprint | libfprint support for Goodix `27c6:6890`, with fprintd enabled |
| Touchpad | Confidence/palm handling and pressure thresholds for `347D:7853` |
| Vendor keys | AI/Mi key press and release events via a replacement WMI driver |

Application shortcuts and desktop actions are yours to configure.

## Configuration

Disable any feature group you don't need:

```nix
hardware.xiaomi-book-pro = {
  enable = true;
  keyboard.enable = false;
  graphics.enable = false;
  fingerprint.enable = false;
  touchpad.enable = false;
  hotkeys.enable = false;
};
```

Kernel versions determine workaround defaults, not restrictions. You can
override them for a backported fix or a regression:

```nix
hardware.xiaomi-book-pro = {
  keyboard.workaround.enable = false; # Default: kernel < 7.2
  graphics.forceProbe.enable = false; # Default: kernel < 6.17
  graphics.psrWorkaround.enable = true; # Default: true
};
```

### Touchpad

```nix
hardware.xiaomi-book-pro.touchpad = {
  mode = "driver"; # Default; alternatives: "udev", "none"
  pressureWorkaround.enable = true;
};
```

- **driver**: replaces `hid-multitouch.ko` to expose confidence-based palm reporting.
- **udev**: uses a `quirks=64` override that drops low-confidence reports.
- **none**: leaves the driver's confidence behavior unchanged. Also disable
  `pressureWorkaround.enable` if you want unchanged pressure thresholds.

The driver mode requires `CONFIG_HID_MULTITOUCH=m`. Its effect on stuck contacts
still needs runtime verification. Reboot to test; don't unload a live touchpad driver.

### Experimental Bitland backend

The default hotkey backend is `redmi`. To try Bitland:

```nix
hardware.xiaomi-book-pro.hotkeys.backend = "bitland";
```

Bitland adds microphone, projection and settings key mappings, along with
firmware power-mode controls for TM2424:

- Standard Linux profiles map to **Quiet / Auto / Full-speed**.
- Native **Quiet / Auto / Full-speed / Turbo / Eco** modes are exposed through
  the control device's `performance_mode` sysfs attribute.
- Turbo and Eco appear as `custom` in the standard platform-profile interface.

This backend requires `CONFIG_BITLAND_MIFS_WMI=m`. The patch is tested against
Linux 7.2.9; other versions may need adaptation. Initial suspend/resume tests
passed in Quiet and Turbo, but broader testing is still needed.
See [Bitland usage and testing notes](docs/bitland.md).

## Compatibility notes

- This profile targets TM2424 and the hardware IDs listed above, not every Xiaomi laptop.
- Keep your kernel and graphics userspace sufficiently up to date.
- Secure Boot module-signature enforcement may require signing replacement modules.
- The fingerprint package builds only `goodixmoc`; unrelated fingerprint readers
  may need a different package configuration. For a package-only override, use
  `overlays.default`.

## Development and documentation

```sh
nix flake check
nix build .#hotkeys  # Default WMI driver
nix build .#bitland # Experimental WMI driver
nix build .#touchpad
nix fmt
```

Standalone builds use this flake's `linuxPackages_latest`; imported NixOS modules
use your configured kernel. Evaluation checks do not replace testing on hardware.

Further details:

- [Hardware investigation](docs/investigation.md)
- [Hotkey investigation](docs/hotkeys.md)
- [Bitland investigation and runtime checks](docs/bitland.md)

## License

Nix configuration, tests, documentation and non-Bitland kernel patches are
GPL-2.0-only. The Bitland patch retains the upstream driver's GPL-2.0-or-later
license. See [LICENSE](LICENSE).
