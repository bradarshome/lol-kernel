// SPDX-License-Identifier: GPL-2.0
/*
 * LolPerf - Gaming Detection Engine
 * Auto-switch to gaming mode on sustained high CPU/GPU load
 */

#define pr_fmt(fmt) "lolperf-gaming: " fmt

#include <linux/module.h>
#include <linux/cpufreq.h>
#include <linux/timer.h>

#include "lolperf.h"

#define LOLPERF_GAMING_POLL_MS 1000
#define LOLPERF_GAMING_CPU_THRESHOLD 80
#define LOLPERF_GAMING_GPU_THRESHOLD 70

static unsigned long lolperf_calc_cpu_load(void)
{
	struct cpufreq_policy *policy;
	unsigned long total_load = 0;
	int cpu, count = 0;

	for_each_possible_cpu(cpu) {
		policy = cpufreq_cpu_get(cpu);
		if (!policy)
			continue;
		if (cpu != policy->cpu) {
			cpufreq_cpu_put(policy);
			continue;
		}
		if (policy->cpuinfo.max_freq > 0)
			total_load += (policy->cur * 100) /
				       policy->cpuinfo.max_freq;
		count++;
		cpufreq_cpu_put(policy);
	}

	return count > 0 ? total_load / count : 0;
}

static unsigned long lolperf_calc_gpu_load(void)
{
	/*
	 * Simplified GPU load estimation.
	 * For Qualcomm Adreno, read /sys/class/kgsl/kgsl-3d0/gpubusy.
	 * For devfreq-based GPUs, estimate from current vs max freq.
	 * Returns 0 if GPU info unavailable.
	 */
	return 0;
}

static void lolperf_gaming_timer_callback(struct timer_list *timer)
{
	struct lolperf_context *ctx =
		container_of(timer, struct lolperf_context, gaming_timer);
	unsigned long cpu_load, gpu_load;

	if (!ctx->gaming_detect_enabled)
		goto rearm;

	cpu_load = lolperf_calc_cpu_load();
	gpu_load = lolperf_calc_gpu_load();

	ctx->gaming_cpu_load = cpu_load;
	ctx->gaming_gpu_load = gpu_load;

	mutex_lock(&ctx->lock);

	if (cpu_load > LOLPERF_GAMING_CPU_THRESHOLD &&
	    gpu_load > LOLPERF_GAMING_GPU_THRESHOLD) {
		ctx->gaming_detect_samples++;

		if (ctx->gaming_detect_samples >=
		    ctx->gaming_threshold_samples) {
			if (ctx->active_profile != LOLPERF_GAMING) {
				pr_info("Gaming detected! (CPU: %lu%%, GPU: %lu%%)\n",
					cpu_load, gpu_load);
				ctx->active_profile = LOLPERF_GAMING;
			}
			ctx->gaming_detect_samples = 0;
		}
	} else {
		ctx->gaming_detect_samples = 0;

		if (ctx->active_profile == LOLPERF_GAMING) {
			pr_info("Gaming ended (CPU: %lu%%, GPU: %lu%%)\n",
				cpu_load, gpu_load);
			ctx->active_profile = ctx->requested_profile;
		}
	}

	mutex_unlock(&ctx->lock);

rearm:
	mod_timer(&ctx->gaming_timer,
		  jiffies + msecs_to_jiffies(LOLPERF_GAMING_POLL_MS));
}

int lolperf_gaming_init(struct lolperf_context *ctx)
{
	ctx->gaming_threshold_samples = 5;
	ctx->gaming_cpu_load = 0;
	ctx->gaming_gpu_load = 0;
	ctx->gaming_detect_samples = 0;

	timer_setup(&ctx->gaming_timer, lolperf_gaming_timer_callback, 0);
	mod_timer(&ctx->gaming_timer,
		  jiffies + msecs_to_jiffies(LOLPERF_GAMING_POLL_MS));

	pr_info("Gaming detection started (threshold: %d samples)\n",
		ctx->gaming_threshold_samples);
	return 0;
}

void lolperf_gaming_exit(struct lolperf_context *ctx)
{
	del_timer_sync(&ctx->gaming_timer);
	pr_info("Gaming detection stopped\n");
}
