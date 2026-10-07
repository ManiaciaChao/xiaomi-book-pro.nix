# Experimental TM2424 Bitland backend

## Scope and source

This branch builds the configured kernel's `bitland-mifs-wmi.c` as a standalone
replacement module. It does not rebuild the whole kernel. Linux 7.2.9 is the
tested source/ABI. The patch is deliberately not a wholesale import of the
older v5 or the v9 consolidation series.

The local adaptation is gated by DMI `XIAOMI` / `TM2424`. The performance
encoding and reduced-firmware behavior follow the
[TM2424 proposal from August 2026](https://lkml.iu.edu/2608.3/05523.html).
Those firmware assumptions were tested by that proposal's author on BIOS
XMAPT4B0P0707. The consumer's BIOS is XMAPT4B0P0A0A; initial read-only
observations and subsequent runtime tests are recorded separately below.

### Read-only consumer observation (2026-10-07)

A temporary one-shot diagnostic module bound the previously unbound control
GUID, invoked method 1 / instance 0 with GET `250` / function `8`, copied the
response, and was unloaded immediately. It had no SET code, platform-profile
registration or suspend/resume callbacks. The existing Redmi event driver was
left in place.

```text
raw=00 80 00 08 09 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
operation=0x80
mode=0x09
```

This confirms that firmware currently reports `0x09`, consistent with the
proposal's Auto encoding and outside the stock driver's generic `0..3` map.
It does not enumerate all supported modes, prove their names, or validate SET
acceptance. No mode-changing requests or sleep tests were performed.

At the same time, the running `SoC Power Slider` provider (`proc_thermal_pci`)
advertised `low-power balanced performance` and reported `performance`.
That Intel interface is distinct from WMI and cannot verify Xiaomi's raw mode
list. With both providers loaded, the global platform-profile view may expose
their common choices; inspect each provider's own profile when diagnosing it.

### Local firmware and Xiaomi utility investigation

Offline disassembly of this machine's DSDT and SSDT25 (BIOS XMAPT4B0P0A0A)
provides stronger evidence than model-name assumptions:

- WMAA GET / function 8 calls `Q_EC.FUNR(0x16)`, which returns the EC's `QFAN`
  field. Its response branches recognize `2`, `3`, `4`, `9`, and `10`.
- WMAA SET / function 8 writes `QFAN` through `ECWT` for those normal modes,
  and has separate branches for `5..8` manipulating additional EC state. These
  are not proof of additional ordinary user-selectable profiles.
- The WMI path also changes Intel mailbox state at MCHBAR + `0x5da0`, notifies
  `IETM` (`INTC10D4`), and uses `NTDP` to update the thermal-policy variable
  `ODV1`. It therefore participates in platform thermal policy, not just a
  separate fan setting.
- Linux 7.2.9's SoC Slider driver writes the optimization hint at MCHBAR +
  `0x5b38` (`performance=0`, `balanced=3`, `low-power=6`). That path does not
  invoke WMAA or write `QFAN`. The interfaces are different controls over an
  overlapping power-management system; firmware/user-space coupling cannot
  be excluded merely because the current mode labels differ.

Important qualification to the GET-only diagnostic: the firmware's GET branch
for Auto (`9`) calls `NTDP`, updating a policy variable and issuing a thermal
notification. No SET was sent and no different raw mode was requested, but a
GET is not guaranteed to be completely side-effect-free inside this firmware.

[XiControl](https://github.com/Oksion/XiControl/blob/main/src/Wmi/Mifs.cs),
developed on TM2424, names `2=Quiet`, `3=Turbo`, `4=FullSpeed`, `9=Auto`, and
`10=Eco`; it documents that Eco can also lower panel brightness and disable
keyboard backlight. Its
[SetPerfMode implementation](https://github.com/Oksion/XiControl/blob/main/src/Wmi/MifsClient.cs)
checks GET readback after SET, not just status.

This matters because the local WMAA SET branch returns status `0x80` even
after falling through an unrecognized mode. The experimental driver's
SET verification now requires successful GET readback of the exact requested
mode, rather than trusting the status alone.

A [September 2026 report on BIOS P0909](https://lkml.iu.edu/2609.3/09954.html)
measured sustained AC package limits of approximately 18 W (`2`), 37 W (`3`),
45 W (`9`), 58 W (`4`), and 18 W (`10`). Those values show substantive power
effects but are not measurements on this machine and do not predict idle
battery draw. That report maps `3` to Linux balanced and `9` to
balanced-performance, unlike our initial three-profile mapping below.
The mapping is provisional and can be adjusted after actual power/noise
measurements; raw suspend restoration does not depend on it.

## Vendor keys

The event device uses the shared GUID `46C93E13-EE9B-4262-8488-563BCA757FEF`.
Select one backend only; Bitland mode blacklists `redmi_wmi` rather than
`bitland_mifs_wmi`. Device names change, but the compositor keysyms do not.

| Payload | Linux key | Behavior |
| --- | --- | --- |
| `0x00002101`, `0x00012101` | `KEY_MICMUTE` | Full click for each event |
| `0x00012301` / `0x00012401` | `KEY_ASSISTANT` | Real make / break |
| `0x00012501` / `0x00012601` | `KEY_CONTROLPANEL` | Real make / break |
| `0x00000101` | `KEY_SWITCHVIDEOMODE` | Full click |
| `0x00001b01`, `0x00011b01` | `KEY_CONFIG` | Full click |

The microphone interpretation remains the same as the Redmi workaround; its
firmware semantics still need verification. Volume and panel brightness use
their existing paths. Four-byte event payloads are accepted: notification
handling only reads the first four bytes, not the reserved trailer.

TM2424 firmware's `QV20` reports performance-mode changes with event ID
`0x16`, whereas the generic Bitland driver uses `0x0f`. The TM2424 dispatcher
routes `0x16` through the platform-profile notifier without emitting a key.
The generic event handling remains unchanged for other machines.

## Platform profiles

| Firmware GET mode | Linux profile | Firmware SET mode |
| --- | --- | --- |
| Quiet `0x02` | `low-power` | Quiet `0x02` |
| Auto `0x09` | `balanced` | Auto `0x09` |
| Full-speed `0x04` | `performance` | Full-speed `0x04` |
| Turbo `0x03`, Eco `0x0a` | `custom` | Select explicitly through the native sysfs attribute |

SET requires status `0x80`, then a successful GET whose raw mode matches the
request. Mismatch returns `-EIO`; firmware rejection returns `-EOPNOTSUPP`.
Writers are serialized across SET/readback using a separate mode mutex.
Transport errors are returned rather than blindly retried. There is no
automatic Full-speed-to-Turbo fallback. The generic circular-DC-jack
requirement does not apply to this USB-C machine. `balanced-performance` is
not advertised for TM2424. Unknown modes remain errors for normal profile
queries, not silently relabeled as balanced.

Suspend/resume does **not** use this lossy mapping to restore a mode. It saves
the validated raw firmware byte and writes that exact byte back on resume:
Quiet stays Quiet and Turbo stays Turbo. Restore also verifies readback;
firmware rejection logs a warning, rather than
silently changing to another mode.

TM2424 does not expose generic RGB keyboard/hwmon/GPU-mode/fan-boost controls
through this adaptation. Its control device registers the platform-profile
interface, native-mode sysfs group and profile notifier. Generic Bitland control interfaces stay
on the non-TM2424 path.

### Native Xiaomi modes via sysfs

Only the TM2424 **control** WMI device exposes these attributes:

| Attribute | Access | Contents |
| --- | --- | --- |
| `performance_mode` | root-writable, readable | `quiet`, `turbo`, `full-speed`, `auto`, or `eco` |
| `performance_mode_available` | read-only | The five recognized names, not an AC/battery capability probe |
| `performance_mode_raw` | read-only | Current firmware byte, including unknown codes, e.g. `0x09` |

After booting the Bitland backend, discover the device rather than assuming a
fixed numeric suffix:

```sh
for dev in /sys/bus/wmi/devices/B60BFB48-3E5B-49E4-A0E9-8CFFE1B3434B-*; do
  [ -f "$dev/performance_mode" ] || continue
  cat "$dev/performance_mode_available" "$dev/performance_mode" "$dev/performance_mode_raw"
  # Explicit mode-changing example; Eco may alter panel/backlight settings:
  # printf '%s\n' eco | run0 tee "$dev/performance_mode"
done
```

Native writes affect Xiaomi WMI only; they do not write Intel's SoC Slider.
Raw reads still validate firmware success status and propagate transport errors,
but do not require the returned mode to be one of the five known values.
Named-mode queries, standard profiles and suspend saves retain that validation.
Successful writes notify the platform-profile framework. Turbo/Eco read back
as `custom` through Linux's standard profile interface, preserving the
distinction from the three standard modes. No CLI or user-space service is
installed. Existing power-management services may subsequently overwrite a
native selection when applying a standard profile.

Writes are not transactional: firmware may have changed the mode before a
readback transport failure, so inspect the mode after any error. Likewise,
Linux's aggregate profile write sets providers sequentially and does not roll
back the Intel provider if Xiaomi rejects Full-speed. Check each provider if
the aggregate write fails.

## Does the reported suspend failure still exist?

The [Fedora report](https://github.com/hzwzwzw/Xiaomi-Book-Pro-14-2026-Linux-Drivers/blob/main/README-cn.md)
describes `bitland_mifs_wmi_suspend returns -22` on Linux 7.1.4.
Inspection of Linux 7.2.9 shows the same failure path:

1. Suspend reads the current firmware performance mode.
2. Generic GET only recognizes modes `0..3`; TM2424 modes `4`, `9`, and `10`
   reach `-EINVAL`.
3. The callback returns that error, aborting suspend.

Thus the risk remains in this kernel's source. No current-boot journal evidence
confirmed it on the consumer, where the previous configuration blacklisted
Bitland. Source inspection is not a successful or failed hardware sleep test.

The local patch fixes the known mapping and treats profile preservation as
best-effort on TM2424: reset validity at each suspend, save only a successful
GET of a recognized raw mode, warn but continue on failure, and skip restore when no valid mode was
saved. Restore failures warn without failing resume. It does not fabricate a
saved profile. Non-TM2424 suspend error behavior is preserved.

This avoids the reported profile-callback blocker directly; no sleep-time
unbind/rebind service is installed. It does not address a separate lid-switch
ACPI bug or establish that deep/S3 is safe. Do not force `mem_sleep_default=deep`
based on this change.

## Verification

### Initial hardware results (2026-10-08)

Tested on TM2424, BIOS XMAPT4B0P0A0A, Linux 7.2.9, NixOS boot generation
127, with power-profiles-daemon 0.30 and the local replacement module.

- The updates-directory Bitland module loaded; Redmi did not load. The user
  confirmed that vendor hotkeys work.
- Standard profiles were observed as Full-speed `0x04` / performance,
  Auto `0x09` / balanced, and Quiet `0x02` / low-power. Intel SoC Slider
  reported the corresponding standard profile in each case.
- Quiet: lid-close s2idle from 00:18:41 to 00:19:47 completed successfully.
  After wake, Xiaomi remained `0x02` and Intel remained low-power.
- Native Turbo was written through sysfs and read back as `0x03`; Xiaomi's
  standard profile became custom while Intel stayed low-power. Lid-close
  s2idle from 00:22:17 to 00:24:04 completed successfully; after wake, Turbo
  `0x03` and Intel low-power were unchanged.
- No profile-save/restore errors or Bitland suspend failures were observed
  in those two cycles. The out-of-tree module taint message is expected.

This is initial coverage, not proof of long-term reliability. Eco switching
and restore, battery-only behavior, rejection/readback-error paths on real
firmware, repeated-cycle stability and mode-dependent power/noise remain
untested. Do not describe all five native modes or every sleep scenario as
hardware-verified. No deep/S3 test was performed.

### Automated checks and further hardware testing

`nix flake check` compiles the real module and tests module selection. A C
harness compiles the actual patched hotkey/profile/PM functions with mocked
kernel and WMI boundaries, covering mode mappings, firmware rejection,
transport errors, make/break semantics, stale-profile prevention and failed
profile saves/restores. All five raw modes must round-trip exactly across
suspend/resume, and rejected restores must not substitute another mode.
Mocks do not exercise real firmware or input delivery.

The actual notification dispatcher is also compiled into the harness: tests
cover TM2424 `0x16` events for each known mode, reject the wrong event type,
preserve generic `0x0f` behavior, and verify assistant make/break delivery.
Raw-read tests cover unknown modes as well as firmware and transport failures.

After booting a configuration with `hotkeys.backend = "bitland"`:

```sh
uname -r
modinfo -n bitland_mifs_wmi
lsmod | grep -E 'bitland_mifs_wmi|redmi_wmi'
grep -A 12 'Bitland MIFS WMI hotkeys' /proc/bus/input/devices
cat /sys/power/mem_sleep
cat /proc/acpi/button/lid/*/state
```

Use `evtest` on the discovered Bitland event device, not a fixed event number.
Verify all table entries, especially one assistant/control-center press and
release each, and ensure no duplicate events from Redmi. Check the relevant
`/sys/class/platform-profile/*/choices` and `profile` files and verify each
supported mode on AC/battery before relying on profile restore.

Test manual suspend and lid-close suspend separately, on AC and battery, then
repeat suspend/resume and check keyboard, touchpad and vendor keys afterward:

```sh
journalctl -b -k --no-pager | grep -E 'bitland|PM:|failed to suspend'
```

Warnings about failed profile save/restore mean sleep continued without a
guaranteed restored profile. They are not proof that firmware profile control
works. Roll back with the previous boot generation or choose backend `redmi`.
