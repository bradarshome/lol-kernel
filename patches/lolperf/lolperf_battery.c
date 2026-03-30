// SPDX-License-Identifier: GPL-2.0
/*
 * LolPerf - Battery Monitor
 * Auto-switch to powersave when battery is low
 */

#define pr_fmt(fmt) "lolperf-battery: " fmt

#include <linux/module.h>
#include <linux/power_supply.h>
#include <linux/workqueue.h>
#include <linux/slab.h>

#include "lolperf.h"

#define LOLPERF_BATTERY_POLL_INTERVAL (10 * HZ)

extern int lolperf_apply_profile_internal(struct lolperf_context *ctx,
					  enum lolperf_profile profile);

static void lolperf_battery_work(struct work_struct *work)
{
	struct lolperf_context *ctx =
		container_of(to_delayed_work(work),
			     struct lolperf_context, battery_work);
	struct power_supply *psy;
	union power_supply_propval val;
	int battery_level, ret;

	if (!ctx->auto_battery_enabled)
		goto reschedule;

	psy = power_supply_get_by_name("battery");
	if (!psy)
		goto reschedule;

	ret = power_supply_get_property(psy, POWER_SUPPLY_PROP_CAPACITY, &val);
	power_supply_put(psy);

	if (ret)
		goto reschedule;

	battery_level = val.intval;

	mutex_lock(&ctx->lock);

	if (battery_level <= ctx->battery_critical_threshold) {
		if (ctx->active_profile != LOLPERF_POWERSAVE) {
			pr_info("Battery critical (%d%%), switching to powersave\n",
				battery_level);
			/* Use internal apply to avoid deadlock */
			ctx->requested_profile = ctx->active_profile;
			ctx->active_profile = LOLPERF_POWERSAVE;
		}
	} else if (battery_level <= ctx->battery_low_threshold) {
		if (ctx->active_profile == LOLPERF_PERFORMANCE ||
		    ctx->active_profile == LOLPERF_GAMING) {
			pr_info("Battery low (%d%%), switching to balanced\n",
				battery_level);
			ctx->requested_profile = ctx->active_profile;
			ctx->active_profile = LOLPERF_BALANCED;
		}
	}

	mutex_unlock(&ctx->lock);

reschedule:
	schedule_delayed_work(&ctx->battery_work,
			      LOLPERF_BATTERY_POLL_INTERVAL);
}

int lolperf_battery_init(struct lolperf_context *ctx)
{
	ctx->battery_low_threshold = 30;
	ctx->battery_critical_threshold = 15;

	INIT_DELAYED_WORK(&ctx->battery_work, lolperf_battery_work);
	schedule_delayed_work(&ctx->battery_work,
			      LOLPERF_BATTERY_POLL_INTERVAL);

	pr_info("Battery monitor started (low: %d%%, critical: %d%%)\n",
		ctx->battery_low_threshold, ctx->battery_critical_threshold);
	return 0;
}

void lolperf_battery_exit(struct lolperf_context *ctx)
{
	cancel_delayed_work_sync(&ctx->battery_work);
	pr_info("Battery monitor stopped\n");
}
