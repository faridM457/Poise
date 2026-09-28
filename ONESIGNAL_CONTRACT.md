# OneSignal messaging contract

The iOS app initializes OneSignal, owns permission UI, records lifecycle events, and synchronizes user tags. It never schedules or sends a remote notification. Remote delivery, quiet hours, timezone handling, frequency caps, and message content remain OneSignal Journey or backend responsibilities.

All timestamps below are Unix timestamps in seconds. Boolean values are the lowercase strings `true` and `false`, matching OneSignal tag storage.

## Tags

| Key | Value type | App lifecycle rule | Journey responsibility |
| --- | --- | --- | --- |
| `subscription_tier` | `free` or `pro` string | Synchronized from the existing RevenueCat `poise_pro` entitlement. | Branch messaging by tier; RevenueCat remains the subscription authority. |
| `streak_count` | Nonnegative integer string | Derived from the persisted session ledger after completion, reset, cloud-ledger changes, entitlement refresh, and preference changes. | Require a value greater than zero for streak-warning messages. |
| `streak_expires_at` | Unix-seconds string, or absent | Set only for an active streak. It is the final second of the calendar day after the most recent practice day. Removed when no active streak exists. | Select the desired warning window before this timestamp and re-check eligibility at send time. |
| `last_practice_at` | Unix-seconds string, or absent | Latest persisted lesson/practice completion. Removed when progress is empty. | Use for inactivity windows and daily-practice eligibility. |
| `weekly_practices_completed` | Nonnegative integer string | Count of persisted completed sessions in the seven calendar days ending today. | Personalize or segment weekly summaries; schedule the weekly send. |
| `daily_reminders_enabled` | Boolean string | Mirrors the local Practice reminders preference. | Require `true` for daily reminders. |
| `streak_alerts_enabled` | Boolean string | Mirrors the local Streak expiration alerts preference. | Require `true` for streak warnings. |
| `weekly_summary_enabled` | Boolean string | Mirrors the local Weekly progress summary preference. | Require `true` for weekly summaries. |
| `custom_scenario_reminders_enabled` | Boolean string | Mirrors the local Custom-scenario reminders preference. | Require `true` for unfinished-scenario reminders. |
| `unfinished_custom_scenario_id` | Stable scenario-ID string, or absent | Set only when roleplay actually starts. Creation and preview do not set it. Removed when that scenario completes. | Build `poise://custom-scenario/<scenario-id>` from this value. |
| `unfinished_custom_scenario_started_at` | Unix-seconds string, or absent | Recorded on the first roleplay start and preserved when the same unfinished scenario resumes. Removed on completion. | Apply the desired inactivity delay/window and suppress stale reminders. |
| `engagement_notification_daily_limit` | Integer string (`2`) | Static frequency-control metadata. | Enforce no more than two engagement notifications per user per local day across Journeys. |

Poise has no authoritative XP ledger, so the app deliberately does not publish a `weekly_xp` tag. Add one only after XP becomes a real persisted product value.

## Events

| Event | Properties | Lifecycle rule |
| --- | --- | --- |
| `lesson_completed` | None | Emitted once when a completed lesson is persisted. |
| `custom_scenario_started` | `scenario_id` string | Emitted when the user taps Start Roleplay, not when a scenario is generated or previewed. |
| `custom_scenario_completed` | `scenario_id` string | Emitted when the completed scorecard is continued and unfinished tags are cleared. |
| `subscription_changed` | `subscription_tier` (`free` or `pro`) | Emitted only when the persisted tier actually changes, not on routine entitlement refreshes. |

## Journey and segment updates

### Streak Alerts

Replace any inferred or fixed-expiration criteria with all of:

1. `streak_alerts_enabled` equals `true`.
2. `streak_count` is greater than `0`.
3. `streak_expires_at` exists and falls inside the chosen pre-expiration window. For a two-hour window, use OneSignal time operators equivalent to elapsed time greater than `-7200` seconds and less than `0` seconds.
4. Re-check the same conditions immediately before delivery, because completing another practice moves the expiration forward and losing the streak removes the timestamp.

### Weekly Summaries

Replace synthetic XP criteria with:

1. `weekly_summary_enabled` equals `true`.
2. Use `weekly_practices_completed` for segmentation and personalization.
3. Schedule the Journey weekly in the recipient's timezone. If empty summaries are unwanted, also require `weekly_practices_completed` greater than `0`.

### Custom Scenario Reminders

Require all of:

1. `custom_scenario_reminders_enabled` equals `true`.
2. `unfinished_custom_scenario_id` exists.
3. `unfinished_custom_scenario_started_at` has exceeded the chosen inactivity delay and remains inside a bounded reminder window.
4. Set the launch URL to `poise://custom-scenario/<unfinished_custom_scenario_id>`.

Completion removes both unfinished tags, so the user exits the segment. The Journey must re-check tag presence before every reminder.

## Launch URLs

- `poise://learn`
- `poise://progress`
- `poise://custom-scenario/<scenario-id>`
- `poise://paywall`

No OneSignal REST API key, APNs private key, or other server credential belongs in the iOS app or repository.
