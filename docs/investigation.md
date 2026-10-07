# TM2424 hardware investigation

Investigated on 2026-10-07 with Linux 7.2.9. Initial extraction preserves the
effective hardware configuration of the original `elio-xbp` host.

## Keyboard

The EC acknowledges the keyboard enable command but can stop scanning after
the driver's deactivate/reset command. A DMI quirk in `atkbd` skips that
deactivation for `XIAOMI` / `Xiaomi Book Pro 14`.

- Absent from upstream v7.1 and v7.2-rc6; present in v7.2-rc7 and v7.2.
- This is separate from the vendor WMI hotkey mappings.
- Dumb keyboard mode was a workaround, but it also prevented ordinary LED
  commands. Removing it may restore LED control; it does not override a
  compositor's choice to repurpose CapsLock.
- Removing `nopnp` together is a local testing policy, not evidence of a
  separately identified PnP fix.

References:

- [Original experimental keyboard patch](https://github.com/EvernightFedora/evernight-vista-patches/blob/main/CachyOS-kernel-extra-patches/keyboard-xiaomi.patch)
- [Upstream v7.2 atkbd source](https://github.com/torvalds/linux/blob/v7.2/drivers/input/keyboard/atkbd.c)
- [Discussion of dumbkbd versus skip-deactivate](https://patchew.org/linux/20260718122437.11112-1-zhoulol888@gmail.com/)

## Graphics

The tested machine reports Intel GPU `8086:b080`, bound to Xe. The old host
configuration specified `b081`, which did not match the actual device.

Upstream v6.16's Panther Lake descriptor required force-probe. v6.17 removed
that requirement. The corresponding platform is not in i915's device table
in the tested kernel. Keep PSR disabled independently: the graphics support
boundary does not prove the panel's PSR issues have been fixed.

- [v6.16 Xe source](https://github.com/torvalds/linux/blob/v6.16/drivers/gpu/drm/xe/xe_pci.c)
- [v6.17 Xe source](https://github.com/torvalds/linux/blob/v6.17/drivers/gpu/drm/xe/xe_pci.c)

## Fingerprint

Goodix MOC USB ID `27c6:6890` needs a libfprint version containing its device
entry. The extracted overlay preserves the original source pin
`d79f157282085738ea8ffbe8c2ae96fb8b3ad831` and the goodixmoc-only build. The
original host noted that commit `3ce7998` introduced the required support;
the pin was the following HEAD at the time of configuration.

WIP: verify an appropriate released libfprint package and remove the override
once the consumer's nixpkgs includes that support. Do not change the source or
enable every driver merely as part of repository extraction.

## Touchpad

The profile now offers mutually exclusive `driver` (default), `udev`, and
`none` confidence modes. In Linux 7.2.9, `347D:7853` matches `MT_CLS_VTL`:
its initialization/multitouch-mode quirk is upstream, but its confidence field
does not enable palm reporting by default. The replacement enables
`MT_QUIRK_CONFIDENCE` when parsing that device's touchpad confidence field,
before the existing `ABS_MT_TOOL_TYPE` registration code. Other VTL quirks
and devices are unchanged. A sysfs write after initialization does not register
that input axis. The legacy value 64 instead discards low-confidence reports,
potentially losing updates or liftoff for an already active contact.

Pressure thresholds remain independent and enabled by default in all modes.
The replacement has been built for Linux 7.2.9; palm reporting, stuck-contact
behavior and suspend/resume require hardware testing after reboot.

The legacy udev mode uses a confidence-bit HID quirk (`64`) and
libinput overrides instead of the optional `hid-multitouch` kernel patch. The
rules apply on add and bind; the libinput settings adjust pressure handling
and the palm-pressure threshold. Tapping preferences stay in the consumer.

## Vendor keys and future driver

See [hotkeys.md](hotkeys.md) for measured payloads, make/break semantics,
microphone uncertainties, verification steps and upstream patch links.

WIP: the base Bitland driver is already upstream, but the v9 consolidation
does not include all TM2424 key mappings. Keep the minimal redmi-wmi fix until
a complete adaptation can replace it, and remove the blacklist at migration.
The default Redmi backend does not provide performance-profile control. An
experimental `hotkeys.backend = "bitland"` now adds local TM2424 hotkey and
performance-profile adaptation; see [bitland.md](bitland.md) for initial
runtime results and remaining test coverage. The adaptation is not upstream.

## Test scope

Build and evaluation checks can prove configuration selection, module ABI and
module priority. Runtime behavior after removing keyboard workarounds still
requires a reboot and actual keyboard/LED/suspend testing. No successful
runtime test is inferred from inspecting a source file.
