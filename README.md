# xiaomi-book-pro.nix

NixOS hardware support for **Xiaomi Book Pro 14 (2026), board TM2424**.
Extracted from a working personal NixOS configuration. This is a hardware
compatibility profile, not a desktop setup or an installer.

**WIP:** the experimental Bitland backend adds local TM2424 hotkey and
platform-profile adaptation. The stable default remains `redmi-wmi` until
the Bitland backend has broader runtime coverage and the adaptation is upstream.
See [the hotkey investigation](docs/hotkeys.md) and
[the hardware notes](docs/investigation.md).

## Use

Add the flake as an input. Until it is published, use an absolute local path:

```nix
inputs.xiaomi-book-pro = {
  url = "path:/absolute/path/to/xiaomi-book-pro.nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Then include the module:

```nix
imports = [ inputs.xiaomi-book-pro.nixosModules.tm2424 ];
hardware.xiaomi-book-pro.enable = true;
```

`nixosModules.default` is an alias for `tm2424`. Importing the module alone does
not enable it. It does not require passing this flake's inputs through
`specialArgs`.

Following the consumer's nixpkgs ensures that the replacement kernel module
uses **the consumer's configured kernel**, not this flake's standalone pin.
No full kernel rebuild is introduced by the hotkey fix.

## Included adaptations

| Feature | Implementation / boundary |
| --- | --- |
| Ordinary keyboard | `nopnp` + `dumbkbd` only below Linux 7.2 |
| Panther Lake GPU | `b080` force-probe parameters only below Linux 6.17 |
| OLED panel | `xe.enable_psr=0` to avoid observed display issues |
| Goodix fingerprint `27c6:6890` | Pinned libfprint source with device support, fprintd enabled |
| Touchpad `347D:7853` | HID confidence-bit and libinput pressure/palm quirks |
| Vendor hotkeys | Out-of-tree `redmi-wmi` replacement, real AI/Mi make/break events |

All five feature groups default to enabled **when the profile is enabled**.
Disable individual groups as needed:

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

The feature groups are stable switches. Kernel versions only determine the
**defaults** of individual workarounds; explicit settings are always honored:

```nix
hardware.xiaomi-book-pro = {
  # Defaults to true below Linux 7.2; force either value for a backport/regression.
  keyboard.workaround.enable = false;
  # Defaults to true below Linux 6.17, independently of the panel workaround.
  graphics.forceProbe.enable = false;
  # Defaults to true; disable only after testing panel stability.
  graphics.psrWorkaround.enable = true;
};
```

These defaults use upstream stable version boundaries, not detection of
downstream backports. The keyboard quirk first appeared in 7.2-rc7, but the
conservative default uses stable 7.2. `nopnp` is paired with `dumbkbd` as a local
policy; no independent upstream version boundary was established for it.

The old-kernel GPU fallback targets the tested unit's PCI ID `b080`. Units with
a different GPU ID need a corresponding adaptation, not an assumption that
this fallback applies unchanged.

The fingerprint overlay deliberately builds only `goodixmoc`, preserving the
original host's configuration. It is not intended to support unrelated external
fingerprint readers. `overlays.default` exports the same overlay for users who
want only the package override without enabling the hardware profile.

The hotkey group blacklists the unselected backend to prevent competition for
the shared WMI event device. Disabling the group removes that blacklist. Secure Boot
module-signature enforcement may require signing the replacement separately.

## Touchpad confidence modes

```nix
hardware.xiaomi-book-pro.touchpad = {
  mode = "driver"; # "driver" (default), "udev", or "none"
  pressureWorkaround.enable = true; # independent libinput thresholds
};
```

- `udev`: preserves the previous `quirks=64` override, dropping reports with
  confidence cleared. This replaces the entire runtime quirk bitmap.
- `driver`: builds only `hid-multitouch.ko` against the selected kernel. For
  I2C `347D:7853` touchpad applications, it enables confidence palm reporting
  during HID parsing, registering `ABS_MT_TOOL_TYPE` and preserving VTL's
  other quirks. No confidence udev override is installed.
- `none`: uses the upstream driver's confidence behavior without a replacement
  or confidence udev rule. Disable `pressureWorkaround.enable` as well for an
  unmodified pressure configuration.

The driver mode requires `CONFIG_HID_MULTITOUCH=m`; a built-in driver cannot
be replaced with this standalone module. Module-signature enforcement may
require signing it separately. Reboot to test; avoid unloading a live touchpad
driver. Improved stuck-contact behavior is a hypothesis, not yet runtime-verified.
Build the standalone replacement with `nix build .#touchpad`.

## Experimental Bitland WMI backend

```nix
hardware.xiaomi-book-pro.hotkeys.backend = "bitland"; # default: "redmi"
```

This builds only `bitland-mifs-wmi.ko` for the consumer's selected kernel and
blacklists `redmi_wmi`. It preserves the assistant/control-center make/break
events and semantic keycodes, adds the microphone/projection/settings mappings,
and exposes TM2424-specific platform profiles. Adaptation is gated by DMI
vendor `XIAOMI` and board `TM2424`.

The TM2424 profile-save callback no longer aborts suspend if firmware mode
reading fails. Restore is skipped when no valid mode was saved. No unbind/rebind
sleep hook or hard-coded WMI device suffix is needed for this failure path.
Initial lid-triggered s2idle suspend/resume passed in Quiet and Turbo on the
tested unit. This does not establish reliability on other firmware or fix
missing lid events or other ACPI firmware problems.

Standard Linux modes map to Quiet / Auto / Full-speed. Native Xiaomi modes
are selectable through the control WMI device's `performance_mode` sysfs
attribute; `performance_mode_available` and `performance_mode_raw` expose
recognized names and the current raw byte. No CLI is installed. Native writes
do not change Intel Slider; Turbo/Eco appear as `custom` in the standard
interface. All mode writes verify GET readback and never silently fall back
to a different mode. See the Bitland notes for examples and error caveats.

Requires `CONFIG_BITLAND_MIFS_WMI=m`. The local patch is tested against Linux
7.2.9; other source revisions may need rebasing. See
[Bitland investigation and runtime checks](docs/bitland.md).

```sh
nix build .#bitland
```

## Kept in the consumer

- Disk layout, UUIDs, filesystem choices, encryption and TPM enrollment.
- Bootloader, Secure Boot keys and choice of kernel package.
- Desktop/compositor, graphics userspace packages and personal input preferences.
- Niri actions for the special keys and application launch/focus behavior.
- Diagnostic utilities and temporary experiments.

Importing this profile does not select a kernel, desktop, partition layout,
or application. A sufficiently recent kernel and graphics userspace are still
the consumer's responsibility.

## Development

```sh
nix flake check
nix build .#hotkeys
nix fmt
```

The standalone package/check uses this flake's `linuxPackages_latest`. In a
consumer, build the actual selected-kernel package with:

```sh
nix build --no-link \
  'path:/path/to/config#nixosConfigurations.HOST.config.hardware.xiaomi-book-pro.hotkeys.package'
```

Module checks cover version boundaries and enabled/disabled profile evaluation.
They are not a substitute for testing input events, microphone behavior,
fingerprint enrollment, touchpad gestures, display stability and suspend/resume
on the machine.

Local path inputs are content-locked: after changing this checkout, update only
the consumer's input with `nix flake update xiaomi-book-pro` before rebuilding.
Do not update unrelated inputs just to refresh this profile.

## Licensing

This repository's Nix configuration, tests and documentation are licensed
under GPL-2.0-only. The Bitland patch retains its upstream driver's
GPL-2.0-or-later licensing; other kernel patches are GPL-2.0-only.
See [LICENSE](LICENSE) for the GPL version 2 text.
