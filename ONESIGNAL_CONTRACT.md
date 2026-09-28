# OneSignal messaging contract

The iOS app initializes OneSignal, owns permission UI, records app events, and synchronizes user tags. It does not schedule or send remote notifications.

## Events

- `lesson_completed`
- `custom_scenario_started` with `scenario_id`
- `custom_scenario_completed` with `scenario_id`
- `subscription_changed` with `subscription_tier` (`free` or `pro`)

## Tags

- `subscription_tier`: `free` or `pro`
- `streak_count`: integer string
- `streak_expires_at`: Unix timestamp in seconds
- `last_practice_at`: Unix timestamp in seconds
- `weekly_xp`: integer string; 10 XP per completed rubric item in the current seven-day window
- `daily_reminders_enabled`: boolean string
- `streak_alerts_enabled`: boolean string
- `weekly_summary_enabled`: boolean string
- `custom_scenario_reminders_enabled`: boolean string
- `engagement_notification_daily_limit`: `2`

## Launch URLs

- `poise://learn`
- `poise://progress`
- `poise://custom-scenario/<scenario-id>`
- `poise://paywall`

The backend or OneSignal Journeys must enforce the two-per-day engagement limit. Exact delivery time, quiet hours, timezone handling, streak-warning timing, and weekly scheduling remain server/Journey responsibilities. No REST API credential belongs in the iOS app.
