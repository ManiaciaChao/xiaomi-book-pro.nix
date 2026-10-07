# SPDX-License-Identifier: GPL-2.0-only
"""Compile the actual patched functions with mocked kernel/WMI boundaries."""

import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
functions = []
for name in (
    "tm2424_profile_read_raw",
    "tm2424_profile_read",
    "tm2424_profile_get",
    "tm2424_profile_write",
    "tm2424_profile_set",
    "platform_profile_probe",
    "bitland_mifs_wmi_suspend",
    "bitland_mifs_wmi_resume",
    "tm2424_report_hotkey",
    "performance_mode_show",
    "performance_mode_store",
    "performance_mode_available_show",
    "performance_mode_raw_show",
    "tm2424_notify_profile_change",
    "bitland_mifs_wmi_notify",
):
    match = re.search(
        r"static (?:int|bool|ssize_t|void) " + name + r"\([^;{}]*\)\n\{", source
    )
    assert match, name
    depth = 1
    end = match.end()
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    functions.append(source[match.start() : end])

keymap = re.search(
    r"static const struct key_entry tm2424_keymap\[\] = \{.*?\n\};", source, re.S
)
assert keymap
harness = pathlib.Path(sys.argv[2]).read_text()
event_types = []
for kind, name in (
    ("enum", "bitland_mifs_event_id"),
    ("enum", "bitland_mifs_event_type"),
    ("enum", "bitland_notifier_actions"),
    ("struct", "bitland_mifs_event"),
    ("struct", "bitland_fan_notify_data"),
):
    match = re.search(kind + " " + name + r" \{.*?\}[^;]*;", source, re.S)
    assert match, name
    event_types.append(match[0])
harness = harness.replace("/* DRIVER EVENT TYPES */", "\n".join(event_types))
mode_names = re.search(
    r"static const char \*const tm2424_mode_names\[\] = \{.*?\n\};", source, re.S
)
mode_values = re.search(
    r"static const u8 tm2424_mode_values\[\] = \{.*?\};", source, re.S
)
assert mode_names and mode_values
print(
    harness.replace(
        "/* DRIVER FUNCTIONS */",
        keymap[0]
        + "\n"
        + mode_names[0]
        + "\n"
        + mode_values[0]
        + "\n"
        + "\n".join(functions),
    )
)
