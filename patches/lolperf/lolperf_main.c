// SPDX-License-Identifier: GPL-2.0
/*
 * LolPerf - Smart Performance Manager for Android GKI
 * Copyright (C) 2026 LolKernel Project
 */

#define pr_fmt(fmt) "lolperf: " fmt

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/cpufreq.h>
#include <linux/devfreq.h>
#include <linux/power_supply.h>
#include <linux/platform_device.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/workqueue.h>
#include <linux/timer.h>
#include <linux/cpumask.h>
#include <linux/device.h>

#include "lolperf.h"

#define LOLPERF_VERSION "1.0.0"
#define LOLPERF_BATTERY_POLL_INTERVAL (10 * HZ)

static struct lolperf_context *g_ctx;

static const char *profile_names[] = {
	"powersave",
	"balanced",
	"performance",
	"gaming",
};

/* ============================================================
 * CPU Control
 * ============================================================ */

static int lolperf_set_cpu_governor(const char *governor)
{
	struct cpufreq_policy *policy;
	int cpu, ret = 0;

	for_each_possible_cpu(cpu) {
		policy = cpufreq_cpu_get(cpu);
		if (!policy)
			continue;
		if (cpu != policy->cpu) {
			cpufreq_cpu_put(policy);
			continue;
		}
		ret = cpufreq_set_policy(policy, governor);
		cpufreq_cpu_put(policy);
		if (ret)
			pr_warn("Failed to set governor '%s' for CPU%d: %d\n",
				governor, cpu, ret);
	}
	return ret;
}

static int lolperf_set_cpu_freq(unsigned long min_freq, unsigned long max_freq)
{
	struct cpufreq_policy *policy;
	int cpu, ret = 0;

	for_each_possible_cpu(cpu) {
		policy = cpufreq_cpu_get(cpu);
		if (!policy)
			continue;
		if (cpu != policy->cpu) {
			cpufreq_cpu_put(policy);
			continue;
		}

		min_freq = max(min_freq, policy->cpuinfo.min_freq);
		max_freq = min(max_freq, policy->cpuinfo.max_freq);

		if (max_freq < policy->min)
			cpufreq_update_policy(policy->cpu);

		policy->min = min_freq;
		policy->max = max_freq;
		ret = cpufreq_update_policy(policy->cpu);
		cpufreq_cpu_put(policy);
		if (ret)
			pr_warn("Failed to set freq CPU%d: %d\n", cpu, ret);
	}
	return ret;
}

/* ============================================================
 * GPU Control via devfreq
 * ============================================================ */

static struct devfreq *lolperf_find_gpu_devfreq(void)
{
	struct device *dev;
	struct class *df_class;
	struct device *df_dev;
	struct devfreq *df = NULL;
	const char *gpu_names[] = {
		"3d00000.qcom,kgsl-3d0",
		"mali",
		"gpu",
		NULL
	};
	int i;

	/* Try known device names */
	for (i = 0; gpu_names[i]; i++) {
		dev = bus_find_device_by_name(&platform_bus_type, NULL,
					      gpu_names[i]);
		if (dev) {
			if (dev->devfreq) {
				df = dev->devfreq;
				put_device(dev);
				return df;
			}
			put_device(dev);
		}
	}

	/* Fallback: scan devfreq class */
	df_class = class_find_by_name("devfreq");
	if (!df_class)
		return NULL;

	class_for_each_device(df_class, NULL, NULL,
			      (int (*)(struct device *, void *))NULL);
	/* Manual iteration needed for older kernels */

	return NULL;
}

static int lolperf_set_gpu_freq(unsigned long min_freq, unsigned long max_freq)
{
	struct devfreq *df;
	int ret = 0;

	df = lolperf_find_gpu_devfreq();
	if (!df)
		return -ENODEV;

	mutex_lock(&df->lock);
	if (df->user_min_freq_req)
		ret = dev_pm_qos_update_request(df->user_min_freq_req,
						min_freq);
	if (df->user_max_freq_req && ret == 0)
		ret = dev_pm_qos_update_request(df->user_max_freq_req,
						max_freq);
	mutex_unlock(&df->lock);
	return ret;
}

/* ============================================================
 * Apply Profile
 * ============================================================ */

struct lolperf_profile_config {
	const char *name;
	const char *cpu_governor;
	unsigned long cpu_min_freq;
	unsigned long cpu_max_freq;
	const char *gpu_governor;
	unsigned long gpu_min_freq;
	unsigned long gpu_max_freq;
};

static const struct lolperf_profile_config profile_configs[] = {
	[LOLPERF_POWERSAVE] = {
		.name = "powersave",
		.cpu_governor = "schedutil",
		.cpu_min_freq = 307200,
		.cpu_max_freq = 1804800,
		.gpu_governor = "msm-adreno-tz",
		.gpu_min_freq = 267000000,
		.gpu_max_freq = 370000000,
	},
	[LOLPERF_BALANCED] = {
		.name = "balanced",
		.cpu_governor = "schedutil",
		.cpu_min_freq = 307200,
		.cpu_max_freq = 3200000,
		.gpu_governor = "msm-adreno-tz",
		.gpu_min_freq = 267000000,
		.gpu_max_freq = 680000000,
	},
	[LOLPERF_PERFORMANCE] = {
		.name = "performance",
		.cpu_governor = "schedutil",
		.cpu_min_freq = 1804800,
		.cpu_max_freq = 3200000,
		.gpu_governor = "msm-adreno-tz",
		.gpu_min_freq = 370000000,
		.gpu_max_freq = 680000000,
	},
	[LOLPERF_GAMING] = {
		.name = "gaming",
		.cpu_governor = "schedutil",
		.cpu_min_freq = 2000000,
		.cpu_max_freq = 3200000,
		.gpu_governor = "msm-adreno-tz",
		.gpu_min_freq = 585000000,
		.gpu_max_freq = 680000000,
	},
};

static int lolperf_apply_profile(struct lolperf_context *ctx,
				 enum lolperf_profile profile)
{
	const struct lolperf_profile_config *config;
	int ret = 0;

	if (profile >= LOLPERF_NUM_PROFILES)
		return -EINVAL;

	config = &profile_configs[profile];
	pr_info("Activating profile: %s\n", config->name);

	if (config->cpu_governor)
		lolperf_set_cpu_governor(config->cpu_governor);
	if (config->cpu_min_freq || config->cpu_max_freq)
		lolperf_set_cpu_freq(config->cpu_min_freq,
				     config->cpu_max_freq);
	if (config->gpu_min_freq || config->gpu_max_freq)
		lolperf_set_gpu_freq(config->gpu_min_freq,
				     config->gpu_max_freq);

	atomic_notifier_call_chain(&ctx->profile_notifier_list,
				   profile, (void *)config->name);

	ctx->active_profile = profile;
	return ret;
}

/* ============================================================
 * Public API
 * ============================================================ */

int lolperf_set_profile(enum lolperf_profile profile)
{
	struct lolperf_context *ctx = g_ctx;
	int ret;

	if (!ctx)
		return -ENODEV;

	mutex_lock(&ctx->lock);
	ctx->requested_profile = profile;
	ret = lolperf_apply_profile(ctx, profile);
	mutex_unlock(&ctx->lock);
	return ret;
}
EXPORT_SYMBOL_GPL(lolperf_set_profile);

enum lolperf_profile lolperf_get_profile(void)
{
	if (!g_ctx)
		return LOLPERF_BALANCED;
	return g_ctx->active_profile;
}
EXPORT_SYMBOL_GPL(lolperf_get_profile);

/* ============================================================
 * Sysfs Interface
 * ============================================================ */

/* /sys/kernel/lolperf/profile */
static ssize_t profile_show(struct kobject *kobj,
			    struct kobj_attribute *attr, char *buf)
{
	struct lolperf_context *ctx = g_ctx;

	if (!ctx || ctx->active_profile >= LOLPERF_NUM_PROFILES)
		return -EINVAL;
	return scnprintf(buf, PAGE_SIZE, "%s\n",
			 profile_names[ctx->active_profile]);
}

static ssize_t profile_store(struct kobject *kobj,
			     struct kobj_attribute *attr,
			     const char *buf, size_t count)
{
	char name[32];
	int i, ret;

	if (count >= sizeof(name))
		return -EINVAL;

	strscpy(name, buf, sizeof(name));
	name[strcspn(name, "\n")] = '\0';

	for (i = 0; i < LOLPERF_NUM_PROFILES; i++) {
		if (sysfs_streq(name, profile_names[i])) {
			ret = lolperf_set_profile(i);
			if (ret)
				return ret;
			return count;
		}
	}
	return -EINVAL;
}

static struct kobj_attribute profile_attr =
	__ATTR(profile, 0644, profile_show, profile_store);

/* /sys/kernel/lolperf/auto_mode */
static ssize_t auto_mode_show(struct kobject *kobj,
			      struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n",
			 g_ctx->auto_battery_enabled ? 1 : 0);
}

static ssize_t auto_mode_store(struct kobject *kobj,
			       struct kobj_attribute *attr,
			       const char *buf, size_t count)
{
	int val, ret;

	ret = kstrtoint(buf, 0, &val);
	if (ret)
		return ret;

	mutex_lock(&g_ctx->lock);
	g_ctx->auto_battery_enabled = (val != 0);
	mutex_unlock(&g_ctx->lock);

	pr_info("Auto mode %s\n", val ? "enabled" : "disabled");
	return count;
}

static struct kobj_attribute auto_mode_attr =
	__ATTR(auto_mode, 0644, auto_mode_show, auto_mode_store);

/* /sys/kernel/lolperf/gaming_detect */
static ssize_t gaming_detect_show(struct kobject *kobj,
				  struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n",
			 g_ctx->gaming_detect_enabled ? 1 : 0);
}

static ssize_t gaming_detect_store(struct kobject *kobj,
				   struct kobj_attribute *attr,
				   const char *buf, size_t count)
{
	int val, ret;

	ret = kstrtoint(buf, 0, &val);
	if (ret)
		return ret;

	mutex_lock(&g_ctx->lock);
	g_ctx->gaming_detect_enabled = (val != 0);
	if (!val)
		g_ctx->gaming_detect_samples = 0;
	mutex_unlock(&g_ctx->lock);

	pr_info("Gaming detection %s\n", val ? "enabled" : "disabled");
	return count;
}

static struct kobj_attribute gaming_detect_attr =
	__ATTR(gaming_detect, 0644, gaming_detect_show, gaming_detect_store);

/* /sys/kernel/lolperf/battery_threshold_low */
static ssize_t battery_low_show(struct kobject *kobj,
				struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", g_ctx->battery_low_threshold);
}

static ssize_t battery_low_store(struct kobject *kobj,
				 struct kobj_attribute *attr,
				 const char *buf, size_t count)
{
	int val, ret;

	ret = kstrtoint(buf, 0, &val);
	if (ret)
		return ret;
	if (val < 0 || val > 100)
		return -EINVAL;
	g_ctx->battery_low_threshold = val;
	return count;
}

static struct kobj_attribute battery_low_attr =
	__ATTR(battery_threshold_low, 0644, battery_low_show,
	       battery_low_store);

/* /sys/kernel/lolperf/battery_threshold_crit */
static ssize_t battery_crit_show(struct kobject *kobj,
				 struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n",
			 g_ctx->battery_critical_threshold);
}

static ssize_t battery_crit_store(struct kobject *kobj,
				  struct kobj_attribute *attr,
				  const char *buf, size_t count)
{
	int val, ret;

	ret = kstrtoint(buf, 0, &val);
	if (ret)
		return ret;
	if (val < 0 || val > 100)
		return -EINVAL;
	g_ctx->battery_critical_threshold = val;
	return count;
}

static struct kobj_attribute battery_crit_attr =
	__ATTR(battery_threshold_crit, 0644, battery_crit_show,
	       battery_crit_store);

/* /sys/kernel/lolperf/status */
static ssize_t status_show(struct kobject *kobj,
			   struct kobj_attribute *attr, char *buf)
{
	struct lolperf_context *ctx = g_ctx;
	struct power_supply *psy;
	union power_supply_propval val;
	int battery_level = -1, battery_status = -1;

	psy = power_supply_get_by_name("battery");
	if (psy) {
		if (!power_supply_get_property(psy,
				POWER_SUPPLY_PROP_CAPACITY, &val))
			battery_level = val.intval;
		if (!power_supply_get_property(psy,
				POWER_SUPPLY_PROP_STATUS, &val))
			battery_status = val.intval;
		power_supply_put(psy);
	}

	return scnprintf(buf, PAGE_SIZE,
		"version: %s\n"
		"profile: %s\n"
		"auto_battery: %s\n"
		"gaming_detect: %s\n"
		"battery_level: %d%%\n"
		"battery_status: %d\n"
		"cpu_load: %lu%%\n"
		"gpu_load: %lu%%\n",
		LOLPERF_VERSION,
		profile_names[ctx->active_profile],
		ctx->auto_battery_enabled ? "enabled" : "disabled",
		ctx->gaming_detect_enabled ? "enabled" : "disabled",
		battery_level,
		battery_status,
		ctx->gaming_cpu_load,
		ctx->gaming_gpu_load);
}

static struct kobj_attribute status_attr =
	__ATTR(status, 0444, status_show, NULL);

/* Attribute group */
static struct attribute *lolperf_attrs[] = {
	&profile_attr.attr,
	&auto_mode_attr.attr,
	&gaming_detect_attr.attr,
	&battery_low_attr.attr,
	&battery_crit_attr.attr,
	&status_attr.attr,
	NULL,
};

static const struct attribute_group lolperf_attr_group = {
	.attrs = lolperf_attrs,
};

/* ============================================================
 * Module Init/Exit
 * ============================================================ */

static int __init lolperf_init(void)
{
	struct lolperf_context *ctx;
	int ret;

	pr_info("LolPerf v%s - Smart Performance Manager\n", LOLPERF_VERSION);

	ctx = kzalloc(sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	g_ctx = ctx;
	mutex_init(&ctx->lock);
	ATOMIC_INIT_NOTIFIER_HEAD(&ctx->profile_notifier_list);

	ctx->active_profile = LOLPERF_BALANCED;
	ctx->requested_profile = LOLPERF_BALANCED;
	ctx->auto_battery_enabled = true;
	ctx->gaming_detect_enabled = true;

	ctx->kobj = kobject_create_and_add("lolperf", kernel_kobj);
	if (!ctx->kobj) {
		ret = -ENOMEM;
		goto err_free;
	}

	ret = sysfs_create_group(ctx->kobj, &lolperf_attr_group);
	if (ret) {
		pr_err("Failed to create sysfs: %d\n", ret);
		goto err_kobj;
	}

	lolperf_battery_init(ctx);
	lolperf_gaming_init(ctx);
	lolperf_apply_profile(ctx, LOLPERF_BALANCED);

	pr_info("Loaded successfully\n");
	pr_info("Interface: /sys/kernel/lolperf/\n");
	pr_info("  echo powersave|balanced|performance|gaming > /sys/kernel/lolperf/profile\n");

	return 0;

err_kobj:
	kobject_put(ctx->kobj);
err_free:
	kfree(ctx);
	g_ctx = NULL;
	return ret;
}

static void __exit lolperf_exit(void)
{
	struct lolperf_context *ctx = g_ctx;

	if (!ctx)
		return;

	lolperf_gaming_exit(ctx);
	lolperf_battery_exit(ctx);
	lolperf_apply_profile(ctx, LOLPERF_BALANCED);

	sysfs_remove_group(ctx->kobj, &lolperf_attr_group);
	kobject_put(ctx->kobj);
	kfree(ctx);
	g_ctx = NULL;

	pr_info("Unloaded\n");
}

module_init(lolperf_init);
module_exit(lolperf_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("LolKernel Project");
MODULE_DESCRIPTION("Smart Performance Manager for Android GKI");
MODULE_VERSION(LOLPERF_VERSION);
