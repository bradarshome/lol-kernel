/* SPDX-License-Identifier: GPL-2.0 */
/*
 * LolPerf - Smart Performance Manager for Android GKI
 * Copyright (C) 2026 LolKernel Project
 */

#ifndef _LOLPERF_H
#define _LOLPERF_H

#include <linux/types.h>
#include <linux/mutex.h>
#include <linux/timer.h>
#include <linux/workqueue.h>
#include <linux/notifier.h>

/* Profile modes */
enum lolperf_profile {
	LOLPERF_POWERSAVE = 0,
	LOLPERF_BALANCED = 1,
	LOLPERF_PERFORMANCE = 2,
	LOLPERF_GAMING = 3,
	LOLPERF_NUM_PROFILES,
};

/* Main driver context */
struct lolperf_context {
	struct mutex lock;
	struct kobject *kobj;

	/* Current profile */
	enum lolperf_profile active_profile;
	enum lolperf_profile requested_profile;

	/* Auto battery monitoring */
	bool auto_battery_enabled;
	int battery_low_threshold;
	int battery_critical_threshold;
	struct delayed_work battery_work;

	/* Gaming detection */
	bool gaming_detect_enabled;
	struct timer_list gaming_timer;
	unsigned long gaming_cpu_load;
	unsigned long gaming_gpu_load;
	int gaming_detect_samples;
	int gaming_threshold_samples;

	/* Notifier for profile changes */
	struct atomic_notifier_head profile_notifier_list;
};

/* API */
int lolperf_set_profile(enum lolperf_profile profile);
enum lolperf_profile lolperf_get_profile(void);

/* Battery */
int lolperf_battery_init(struct lolperf_context *ctx);
void lolperf_battery_exit(struct lolperf_context *ctx);

/* Gaming */
int lolperf_gaming_init(struct lolperf_context *ctx);
void lolperf_gaming_exit(struct lolperf_context *ctx);

#endif /* _LOLPERF_H */
