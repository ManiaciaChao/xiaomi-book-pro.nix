# Xiaomi Book Pro 14 hotkeys — WIP

**WIP: migrate to `bitland-mifs-wmi` when the upstream driver consolidation
and complete TM2424 hotkey support are available.** This is a temporary,
hotkey-only fix for the existing `redmi-wmi` driver, not a performance-control
driver or a copy of the full Bitland patch series.

## Enable

Import the flake's `nixosModules.tm2424` and set:

```nix
hardware.xiaomi-book-pro.enable = true;
```

The consumer enables the module on `elio-xbp`. It builds `redmi-wmi.ko` against
`boot.kernelPackages.kernel`, using that kernel's source and prepared build
environment. Only the driver is compiled; the kernel derivation is not patched
or rebuilt. Kernel upgrades require rebuilding this module.

The replacement is installed under `lib/modules/<version>/updates`, with a
depmod override so it takes precedence over the in-tree copy. The stock module
is retained. `bitland_mifs_wmi` is blacklisted because it matches the same WMI
event GUID and must not take ownership of the event device. This intentionally
also prevents its hardware-control interface from loading automatically.

## Findings (2026-10-07)

- DMI product: `Xiaomi Book Pro 14`; vendor: `XIAOMI`.
- Running kernel during investigation: `7.2.9`.
- The special keys are on a separate input device named `Redmibook WMI keys`,
  observed as `event4`; event numbers are not stable and must not be hardcoded.
- Driver: `redmi-wmi`; event GUID:
  `46C93E13-EE9B-4262-8488-563BCA757FEF`.
- Normal F-key events work. Several special-function events never reached
  evtest because the driver's sparse keymap did not recognize their payloads.
- Unknown events are logged with `dev_dbg`, so ordinary kernel logs were silent.
  Enabling dynamic debug exposed the missing payloads.

| Physical key | WMI payload(s) | Linux input code | Niri/XKB keysym |
| --- | --- | --- | --- |
| F4 microphone | `0x00002101`, `0x00012101` | `KEY_MICMUTE` | `XF86AudioMicMute` |
| F7 Xiao AI | make `0x00012301`, break `0x00012401` | `KEY_ASSISTANT` | `XF86Assistant` |
| F8 projection | `0x00000101` | `KEY_SWITCHVIDEOMODE` | `XF86Display` |
| F9 settings (already supported) | `0x00001b01`, `0x00011b01` | `KEY_CONFIG` | `XF86Tools` |
| Independent Mi control-center key | make `0x00012501`, break `0x00012601` | `KEY_CONTROLPANEL` | `XF86ControlPanel` |

The F7 and Mi make/break pairs were verified by holding the keys before release.
Report actual press/release events instead of treating both payloads as clicks.
The existing assistant-key behavior on older models is preserved.

Both microphone payloads are treated as complete `KEY_MICMUTE` clicks, matching
the upstream proposal. The user observed them alongside mute-on/mute-off, but
the upstream patch describes them as Fn-lock variants. Do not assume they are
reliable absolute mute-state notifications without further testing. In
particular, test whether firmware already mutes capture before adding a desktop
mute toggle, to avoid double handling.

The names deliberately describe the keys' purposes rather than borrowing F13
or arbitrary programmable keys. The earlier TM2424 proposal used `KEY_PROG1`
and `KEY_VENDOR` for AI/Mi; this local patch uses `KEY_ASSISTANT` and
`KEY_CONTROLPANEL` instead. Recognition does not launch an application: desktop
actions belong in Niri/DMS configuration and are not added by this module.

## Upstream status and references

The base `bitland-mifs-wmi` driver is already in mainline and in the tested
kernel, but its presence does not imply complete support for this machine.

- [Current redmi-wmi source](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/redmi-wmi.c)
- [Current bitland-mifs-wmi source](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/bitland-mifs-wmi.c)
- [Driver consolidation v9, submitted 2026-10-01](https://patchew.org/linux/20261001133705.69244-1-qby140326@gmail.com/)
- [Separate TM2424 ops and hotkeys proposal, 2026-08-26](https://lkml.iu.edu/2608.3/05523.html)
- [ArchWiki function-key table](https://wiki.archlinux.org/title/Xiaomi_Book_Pro_14#Function_keys)
- [Same-model Linux investigation](https://github.com/YooLc/xiaomi-book-pro-quirks)
- [XiControl, a Windows WMI utility](https://github.com/Oksion/XiControl)

Inspection of v9 found microphone mappings and the AI make event, but not the
TM2424 projection value-0 event, AI break, or Mi make/break entries. The separate
TM2424 patch was based on v5 and also included performance-profile changes.
No confirmed mainline inclusion of that complete adaptation was found during
this investigation. There is no established reason for its omission from v9;
do not interpret it as a confirmed rejection.

## Build and verify

Build-time validation on 2026-10-07 succeeded for kernel `7.2.9`: the standalone
module and combined NixOS module tree both built, vermagic matched, and
`modinfo` / `modprobe --show-depends` selected `updates/redmi-wmi.ko` rather than
the stock module. Hardware event validation after loading the replacement is
still pending; these checks do not prove runtime behavior.

Build the standalone package from this repository with `nix build .#hotkeys`.
To build against the original consumer's actual configured kernel (its
unrelated local kmscon experiment currently requires `--impure`):

```sh
nix build --impure --no-link --print-out-paths \
  'path:/home/elio/nix-config#nixosConfigurations.elio-xbp.config.hardware.xiaomi-book-pro.hotkeys.package'
```

After rebuilding the system and rebooting into that generation:

```sh
modinfo -n redmi_wmi
readlink -f /sys/bus/wmi/devices/46C93E13-EE9B-4262-8488-563BCA757FEF-0/driver
sudo evtest
```

The selected module should be under `updates/redmi-wmi.ko`, the bound driver
should be `redmi-wmi`, and the device should report the codes above. Verify one
press and one release for F7/Mi; one complete click per microphone/projection
activation; and unchanged behavior for existing keys. Use `wev` in the desktop
session to check the XKB names before adding Niri bindings. Do not bind F7/F8,
which are the ordinary function keys rather than these vendor-function events.

For temporary diagnostics:

```sh
echo 'module redmi_wmi +p' | sudo tee /proc/dynamic_debug/control
sudo journalctl -kf
# Disable debug logging after testing:
echo 'module redmi_wmi -p' | sudo tee /proc/dynamic_debug/control
```

Rebooting is preferred to live unloading/rebinding of the WMI driver. If the
kernel enforces module signatures, the replacement must also be signed with
a trusted key; the Nix package alone does not provide that signing policy.

## Migration checklist

- Confirm the upstream Bitland driver supports all payloads measured above.
- Check make/break behavior, microphone semantics, and any changed keysyms.
- Remove this replacement package and the Bitland blacklist together.
- Verify special keys and existing keys on the actual machine.
- Keep performance-profile adaptation separate from this hotkey-only fix.
