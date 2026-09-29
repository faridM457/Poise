# OneSignal messaging contract

The iOS app initializes OneSignal, owns permission UI, records app events, and synchronizes user tags. It does not schedule or send remote notifications.

## Events

- `lesson_completed`
- `custom_scenario_started` with `scenario_id`
- `custom_scenario_completed` with `scenario_id`
- `subscription_changed` with `subscription_tier` (`free` or `pro`)

## Tags

The OneSignal plan allows at most 10 tags per user, and an update that would exceed that is rejected entirely. These are exactly 10; adding a tag means removing one.

- `streak_count`: integer string
- `streak_expires_at`: Unix timestamp in seconds
- `last_practice_at`: Unix timestamp in seconds
- `weekly_sessions_completed`: integer string; conversations finished in the last seven days
- `weekly_criteria_met`: integer string; criteria met across those conversations
- `daily_reminders_enabled`: boolean string
- `streak_alerts_enabled`: boolean string
- `weekly_summary_enabled`: boolean string
- `custom_scenario_reminders_enabled`: boolean string
- `has_unfinished_custom_scenario`: boolean string; true between `custom_scenario_started` and `custom_scenario_completed`

Retired, and actively removed from existing users: `weekly_xp`, `engagement_notification_daily_limit`, `subscription_tier` (tier changes are still sent as the `subscription_changed` event).

## Launch URLs

- `poise://learn`
- `poise://progress`
- `poise://custom-scenario/<scenario-id>`
- `poise://paywall`

The backend or OneSignal Journeys must enforce the two-per-day engagement limit. Exact delivery time, quiet hours, timezone handling, streak-warning timing, and weekly scheduling remain server/Journey responsibilities. No REST API credential belongs in the iOS app.
