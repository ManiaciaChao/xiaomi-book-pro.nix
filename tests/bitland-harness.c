/* SPDX-License-Identifier: GPL-2.0-only */
#include <assert.h>
#include <errno.h>
#include <linux/input-event-codes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
#define __packed __attribute__((packed))
/* DRIVER EVENT TYPES */
enum platform_profile_option {
	PLATFORM_PROFILE_LOW_POWER,
	PLATFORM_PROFILE_BALANCED,
	PLATFORM_PROFILE_BALANCED_PERFORMANCE,
	PLATFORM_PROFILE_PERFORMANCE,
	PLATFORM_PROFILE_CUSTOM
};
enum { WMI_METHOD_GET = 250, WMI_METHOD_SET = 251, WMI_FN_SYSTEM_PER_MODE = 8 };
struct bitland_mifs_input {
	u8 reserved1, operation, reserved2, function, payload[28];
};
struct bitland_mifs_output {
	u8 reserved1, operation, reserved2, function, data[28];
};
struct device {
	void *data;
};
struct device_attribute {
	int unused;
};
struct wmi_device {
	struct device dev;
};
struct wmi_buffer {
	size_t length;
	void *data;
};
struct input_dev {
	int unused;
};
struct bitland_mifs_wmi_data {
	struct wmi_device *wdev;
	struct device *pp_dev;
	struct input_dev *input_dev;
	enum platform_profile_option saved_profile;
	bool saved_profile_valid, tm2424;
	u8 saved_tm2424_mode;
	int lock, mode_lock;
};
enum { KE_END, KE_KEY };
struct key_entry {
	int type;
	u32 code;
	union {
		unsigned short keycode;
	};
};
static int transport_error, calls, reports, report_value;
static bool reject_full, reject_all, report_autorelease, ignore_set, reject_get;
static int notifications;
static int bitland_notifier_list, profile_chain_notifications,
    generic_key_reports;
static u8 firmware_mode, written_modes[8];
static u32 report_code;
static unsigned short report_key;
static struct device *expected_profile_device;

#define dev_warn(...) ((void)0)
#define dev_warn_ratelimited(...) ((void)0)
#define dev_dbg(...) ((void)0)
#define guard(kind) int *unused_lock __attribute__((unused)) =
#define ARRAY_SIZE(a) ((int)(sizeof(a) / sizeof((a)[0])))
#define sysfs_emit(buf, ...) snprintf(buf, 4096, __VA_ARGS__)
static int match_mode(const char *const *names, int size, const char *buf)
{
	for (int i = 0; i < size; i++) {
		size_t len = strlen(names[i]);
		if (strncmp(buf, names[i], len) == 0 &&
		    (buf[len] == '\0' ||
		     (buf[len] == '\n' && buf[len + 1] == '\0')))
			return i;
	}
	return -EINVAL;
}
#define sysfs_match_string(names, buf) match_mode(names, ARRAY_SIZE(names), buf)
static void platform_profile_notify(struct device *dev)
{
	assert(dev == expected_profile_device);
	notifications++;
}
static int blocking_notifier_call_chain(int *head, unsigned long action,
					void *data)
{
	assert(head == &bitland_notifier_list);
	if (action == BITLAND_NOTIFY_PLATFORM_PROFILE)
		profile_chain_notifications++;
	return 0;
}
static u32 get_unaligned_le32(const void *ptr)
{
	const u8 *bytes = ptr;
	return bytes[0] | ((u32)bytes[1] << 8) | ((u32)bytes[2] << 16) |
	       ((u32)bytes[3] << 24);
}
static bool sparse_keymap_report_event(struct input_dev *input, u32 code,
				       int value, bool autorelease)
{
	generic_key_reports++;
	return true;
}
static void *dev_get_drvdata(struct device *dev) { return dev->data; }
static void set_bit(unsigned int bit, unsigned long *bits)
{
	*bits |= 1UL << bit;
}
static int tm2424_profile_get(struct bitland_mifs_wmi_data *,
			      enum platform_profile_option *);
static int tm2424_profile_set(struct bitland_mifs_wmi_data *,
			      enum platform_profile_option);
static int laptop_profile_get(struct device *dev,
			      enum platform_profile_option *profile)
{
	assert(dev == expected_profile_device);
	return tm2424_profile_get(dev->data, profile);
}
static int laptop_profile_set(struct device *dev,
			      enum platform_profile_option profile)
{
	assert(dev == expected_profile_device);
	return tm2424_profile_set(dev->data, profile);
}
static int bitland_mifs_wmi_call(struct bitland_mifs_wmi_data *data,
				 const struct bitland_mifs_input *input,
				 struct bitland_mifs_output *output)
{
	assert(input->function == WMI_FN_SYSTEM_PER_MODE);
	if (input->operation == WMI_METHOD_SET) {
		assert(calls < 8);
		written_modes[calls] = input->payload[0];
	}
	calls++;
	if (transport_error)
		return transport_error;
	if (input->operation == WMI_METHOD_GET) {
		output->operation = reject_get ? 0xe0 : 0x80;
		output->data[0] = firmware_mode;
	} else {
		output->operation =
		    reject_all || (reject_full && input->payload[0] == 4)
			? 0
			: 0x80;
		if (output->operation == 0x80 && !ignore_set)
			firmware_mode = input->payload[0];
	}
	return 0;
}
static const struct key_entry *
sparse_keymap_entry_from_scancode(struct input_dev *, u32);
static void sparse_keymap_report_entry(struct input_dev *input,
				       const struct key_entry *entry, int value,
				       bool autorelease)
{
	reports++;
	report_code = entry->code;
	report_key = entry->keycode;
	report_value = value;
	report_autorelease = autorelease;
}

/* DRIVER FUNCTIONS */

static void dispatch_event(struct wmi_device *wdev, u32 code)
{
	u8 bytes[4] = {code, code >> 8, code >> 16, code >> 24};
	struct wmi_buffer buffer = {.length = sizeof(bytes), .data = bytes};
	bitland_mifs_wmi_notify(wdev, &buffer);
}

static const struct key_entry *
sparse_keymap_entry_from_scancode(struct input_dev *input, u32 code)
{
	for (const struct key_entry *entry = tm2424_keymap;
	     entry->type != KE_END; entry++)
		if (entry->code == code)
			return entry;
	return NULL;
}

int main(void)
{
	struct wmi_device wdev = {0};
	struct device pp = {0};
	struct input_dev input = {0};
	struct bitland_mifs_wmi_data data = {
	    .wdev = &wdev, .pp_dev = &pp, .input_dev = &input, .tm2424 = true};
	wdev.dev.data = &data;
	pp.data = &data;
	expected_profile_device = &pp;
	enum platform_profile_option profile;
	const u8 modes[] = {2, 10, 9, 3, 4};
	const enum platform_profile_option profiles[] = {
	    PLATFORM_PROFILE_LOW_POWER, PLATFORM_PROFILE_CUSTOM,
	    PLATFORM_PROFILE_BALANCED, PLATFORM_PROFILE_CUSTOM,
	    PLATFORM_PROFILE_PERFORMANCE};
	for (unsigned int i = 0; i < sizeof(modes); i++) {
		firmware_mode = modes[i];
		assert(tm2424_profile_get(&data, &profile) == 0);
		assert(profile == profiles[i]);
	}
	firmware_mode = 0xff;
	assert(tm2424_profile_get(&data, &profile) == -EINVAL);
	unsigned long choices = 0;
	assert(platform_profile_probe(&data, &choices) == 0);
	assert(choices == ((1UL << PLATFORM_PROFILE_LOW_POWER) |
			   (1UL << PLATFORM_PROFILE_BALANCED) |
			   (1UL << PLATFORM_PROFILE_PERFORMANCE)));
	calls = 0;
	assert(tm2424_profile_set(&data, PLATFORM_PROFILE_LOW_POWER) == 0 &&
	       written_modes[0] == 2 && calls == 2);
	calls = 0;
	assert(tm2424_profile_set(&data, PLATFORM_PROFILE_BALANCED) == 0 &&
	       written_modes[0] == 9);
	calls = 0;
	reject_full = true;
	assert(tm2424_profile_set(&data, PLATFORM_PROFILE_PERFORMANCE) ==
	       -EOPNOTSUPP);
	assert(calls == 1 && written_modes[0] == 4);
	reject_full = false;
	calls = 0;
	ignore_set = true;
	firmware_mode = 9;
	assert(tm2424_profile_set(&data, PLATFORM_PROFILE_PERFORMANCE) ==
		   -EIO &&
	       calls == 2);
	ignore_set = false;
	reject_get = true;
	assert(tm2424_profile_get(&data, &profile) == -EOPNOTSUPP);
	reject_get = false;
	calls = 0;
	transport_error = -EIO;
	assert(tm2424_profile_set(&data, PLATFORM_PROFILE_PERFORMANCE) ==
		   -EIO &&
	       calls == 1);
	transport_error = 0;
	assert(
	    tm2424_profile_set(&data, PLATFORM_PROFILE_BALANCED_PERFORMANCE) ==
	    -EOPNOTSUPP);
	char buf[4096];
	const char *names[] = {"quiet", "eco", "auto", "turbo", "full-speed"};
	for (unsigned int i = 0; i < sizeof(modes); i++) {
		calls = 0;
		assert(performance_mode_store(&wdev.dev, NULL, names[i],
					      strlen(names[i])) ==
		       (ssize_t)strlen(names[i]));
		assert(firmware_mode == modes[i] && calls == 2);
		assert(performance_mode_show(&wdev.dev, NULL, buf) > 0);
		buf[strcspn(buf, "\n")] = '\0';
		assert(strcmp(buf, names[i]) == 0);
		assert(performance_mode_raw_show(&wdev.dev, NULL, buf) > 0);
		assert(strtoul(buf, NULL, 0) == modes[i]);
	}
	assert(notifications == 5);
	assert(performance_mode_available_show(&wdev.dev, NULL, buf) > 0);
	assert(strcmp(buf, "quiet turbo full-speed auto eco\n") == 0);
	calls = 0;
	assert(performance_mode_store(&wdev.dev, NULL, "invalid", 7) ==
		   -EINVAL &&
	       calls == 0);
	reject_all = true;
	assert(performance_mode_store(&wdev.dev, NULL, "quiet", 5) ==
	       -EOPNOTSUPP);
	assert(notifications == 5);
	reject_all = false;
	calls = 0;
	assert(performance_mode_store(&wdev.dev, NULL, "quiet\n", 6) == 6);
	assert(firmware_mode == 2 && notifications == 6);
	firmware_mode = 0xff;
	/* Invalid profile must neither abort sleep nor restore a stale profile.
	 */
	data.saved_profile_valid = true;
	calls = 0;
	assert(bitland_mifs_wmi_suspend(&wdev.dev) == 0 &&
	       !data.saved_profile_valid);
	assert(bitland_mifs_wmi_resume(&wdev.dev) == 0 && calls == 1);
	transport_error = -EIO;
	assert(bitland_mifs_wmi_suspend(&wdev.dev) == 0);
	data.tm2424 = false;
	assert(bitland_mifs_wmi_suspend(&wdev.dev) == -EIO);
	data.tm2424 = true;
	transport_error = 0;
	firmware_mode = 9;
	assert(bitland_mifs_wmi_suspend(&wdev.dev) == 0 &&
	       data.saved_profile_valid);
	calls = 0;
	assert(bitland_mifs_wmi_resume(&wdev.dev) == 0 && calls == 2 &&
	       written_modes[0] == 9);
	/* Every firmware alias must round-trip exactly, including Quiet and
	 * Turbo. */
	reject_full = false;
	for (unsigned int i = 0; i < sizeof(modes); i++) {
		firmware_mode = modes[i];
		calls = 0;
		assert(bitland_mifs_wmi_suspend(&wdev.dev) == 0);
		assert(data.saved_profile_valid &&
		       data.saved_tm2424_mode == modes[i]);
		calls = 0;
		assert(bitland_mifs_wmi_resume(&wdev.dev) == 0);
		assert(calls == 2 && written_modes[0] == modes[i]);
	}
	/* Restore rejection must not silently substitute a different mode. */
	reject_full = true;
	calls = 0;
	assert(bitland_mifs_wmi_resume(&wdev.dev) == 0);
	assert(calls == 1 && written_modes[0] == 4);
	reject_all = true;
	assert(bitland_mifs_wmi_resume(&wdev.dev) == 0);
	data.pp_dev = NULL;
	calls = 0;
	assert(bitland_mifs_wmi_suspend(&wdev.dev) == 0);
	assert(bitland_mifs_wmi_resume(&wdev.dev) == 0 && calls == 0);
	assert(tm2424_report_hotkey(&data, 0x00012301));
	assert(report_key == KEY_ASSISTANT && report_value == 1 &&
	       !report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00012401));
	assert(report_key == KEY_ASSISTANT && report_value == 0 &&
	       !report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00012501));
	assert(report_key == KEY_CONTROLPANEL && report_value == 1 &&
	       !report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00012601));
	assert(report_key == KEY_CONTROLPANEL && report_value == 0 &&
	       !report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00002101));
	assert(report_key == KEY_MICMUTE && report_value == 1 &&
	       report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00012101));
	assert(report_key == KEY_MICMUTE && report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00000101));
	assert(report_key == KEY_SWITCHVIDEOMODE && report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00001b01));
	assert(report_key == KEY_CONFIG && report_autorelease);
	assert(tm2424_report_hotkey(&data, 0x00011b01));
	assert(report_key == KEY_CONFIG);
	int previous_reports = reports;
	assert(!tm2424_report_hotkey(&data, 0xdeadbeef) &&
	       reports == previous_reports);
	assert(report_code == 0x00011b01);
	/* Exercise the real notify dispatcher with the local BIOS event IDs. */
	int before = reports;
	dispatch_event(&wdev, 0x00012301);
	assert(reports == before + 1 && report_key == KEY_ASSISTANT &&
	       report_value == 1);
	dispatch_event(&wdev, 0x00012401);
	assert(reports == before + 2 && report_key == KEY_ASSISTANT &&
	       report_value == 0);
	for (unsigned int i = 0; i < sizeof(modes); i++)
		dispatch_event(&wdev, 0x00001601 | ((u32)modes[i] << 16));
	assert(profile_chain_notifications == 5 && generic_key_reports == 0);
	assert(reports == before + 2);
	dispatch_event(&wdev, 0x00001602); /* Wrong event type. */
	assert(profile_chain_notifications == 5);
	data.tm2424 = false;
	dispatch_event(&wdev, 0x00091601);
	assert(profile_chain_notifications ==
	       5); /* Generic Bitland path unchanged. */
	dispatch_event(&wdev, 0x00090f01);
	assert(profile_chain_notifications == 6);
	data.tm2424 = true;
	/* Unknown modes remain inspectable through raw, not normal profile
	 * APIs. */
	firmware_mode = 0x55;
	assert(performance_mode_raw_show(&wdev.dev, NULL, buf) > 0);
	assert(strcmp(buf, "0x55\n") == 0);
	assert(performance_mode_show(&wdev.dev, NULL, buf) == -EINVAL);
	assert(tm2424_profile_get(&data, &profile) == -EINVAL);
	reject_get = true;
	assert(performance_mode_raw_show(&wdev.dev, NULL, buf) == -EOPNOTSUPP);
	reject_get = false;
	transport_error = -EIO;
	assert(performance_mode_raw_show(&wdev.dev, NULL, buf) == -EIO);
	puts("TM2424 hotkey, profile and suspend/resume behavior tests passed");
	return 0;
}
