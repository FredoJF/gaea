# Contract: External Platform Callbacks

**Governed by**: [ADR-0007](../../../docs/adr/0007-external-alert-transports.md). Callbacks are
received by the web process (spec 002) because it is the process with a public surface; the work
belongs to this feature and is handed over through the database.

Both endpoints are unauthenticated by nature — anyone on the internet can POST to them. Each must
verify its platform's signature **before parsing the body or taking any action**, and each is
rate-limited independently of dashboard traffic so that callback volume cannot degrade the
dashboard, or vice versa.

## Twitch EventSub (webhook transport)

**Subscription type**: `stream.online`, one per distinct broadcaster followed across the deployment
— not one per guild subscription (FR-035b). Cost is charged per subscription, and a `stream.online`
subscription for a broadcaster who has not authorised the application costs **1** (Twitch Developer
Docs, *Managing Subscriptions*, verified 2026-09-16). At V1's ceiling of 100 distinct broadcasters
the total cost is 100.

**Why webhook and not WebSocket**: the WebSocket transport permits a total cost of **10** across all
subscriptions, which would cap the entire deployment at ten streamers. This is not a scale
consideration that V1's small size relaxes — ten is below what a single active guild would want.

**Verification**: HMAC-SHA256 over the message id, timestamp, and raw body, supplied in
`Twitch-Eventsub-Message-Signature`, compared in constant time. A timestamp outside a narrow window
is rejected as a replay. Verification precedes deserialization (FR-035d).

The per-subscription secret must be an ASCII string of 10 to 100 characters, generated from a
CSPRNG — the platform enforces that length range, and Principle I requires the entropy.

**Message types**: `webhook_callback_verification` (echo the challenge), `notification`, and
`revocation`.

**Revocation is not an edge case.** Twitch revokes subscriptions on its own initiative and states a
reason, each needing distinct handling (FR-035e):

| Reason | Meaning | Response |
|---|---|---|
| `notification_failures_exceeded` | This application responded too slowly, too often | A defect here, not upstream. Must alarm, not just log |
| `user_removed` | The broadcaster is no longer a Twitch user | Retire the guild subscriptions and tell the operator why |
| `version_removed` | The subscription type version is no longer supported | The application must be updated; surfaces as a deployment-level fault |
| `authorization_revoked` | The user withdrew authorization | Not applicable to `stream.online`, but must be handled rather than crashed on |
| `moderator_removed` | Moderator status lost | As above |

Silently discarding a revocation means the feature stops working with nothing anywhere indicating
why — the single most likely way this feature dies quietly in production.

**Deduplication**: Twitch may redeliver. The message id is recorded; a repeat is acknowledged and
discarded. Independently, `last_announced_broadcast_id` on each subscription suppresses a second
alert for the same broadcast, including across a reconnect within the FR-032 window.

**Response discipline — the sharpest constraint in this contract.** Twitch requires notifications to
be acknowledged within seconds, and revokes a subscription whose delivery failure rate is too high.
Its documentation's own advice is to write the notification to storage and process it after
responding 2XX.

The failure mode is what makes this non-negotiable (FR-035c): a handler that announces to Discord
*before* acknowledging is coupled to Discord's latency. A Discord slowdown, or simply a busy moment,
accumulates delivery failures and Twitch unsubscribes the application from **every streamer at
once** — a total, correlated, silent loss of the feature, caused by load elsewhere. So the callback
persists and acknowledges; announcing is separate work on a separate path.

**Duplicate subscription creation**: recreating an existing subscription after a restart must be
treated as success, not as an error (FR-035g), or a restart can leave guilds silently unsubscribed.

**API rate limiting**: streamer validation at subscription time and reconciliation queries honour the
800-point bucket reported via `Ratelimit-Limit`, `Ratelimit-Remaining` and `Ratelimit-Reset`, and
wait for the stated reset instant on a 429 (FR-035f). At V1 scale a full reconciliation queries up
to 100 broadcasters in one `Get Streams` call — one point out of 800 per minute.

## YouTube WebSub

**Hub**: `pubsubhubbub.appspot.com`. **Topic**: the channel feed at
`youtube.com/feeds/videos.xml?channel_id=…`, one subscription per distinct channel followed.

**Verification**: the hub performs a subscribe/unsubscribe confirmation challenge that must be
echoed. Content notifications are verified against the shared secret supplied at subscription time.

**Leases expire.** This is the failure mode that matters: a lease that lapses without renewal
produces no error anywhere, it simply means that channel's uploads are never announced again.
`lease_expires_at` is stored per subscription, renewal is scheduled ahead of it, and a failed
renewal is recorded as an operator-visible fault (FR-042c, and FR-025 of 002) rather than a log line
nobody reads.

The lease length is **chosen by the hub, not by this application**. Renewal must be scheduled from
the `lease_seconds` returned in the subscription confirmation, never from a hardcoded interval —
assuming a duration is how a renewal schedule silently drifts past expiry.

One subscription per distinct YouTube channel across the deployment, fanned out to subscribing
guilds (FR-042d), for the same reason as Twitch. **The YouTube Data API is not used at all**, so its
10,000-unit daily quota is entirely unconsumed and no API key is needed on the alert path.

**Deduplication**: the feed redelivers on edits. FR-038 requires at most one alert per video
regardless, enforced by uniqueness on announced video identifiers. FR-039 requires nothing published
before `subscribed_at` to be announced — relevant because the feed carries a back catalogue on first
delivery. The feed holds only a limited number of recent entries, so the cutoff is evaluated against
each entry's publication time rather than against its position in the feed.

**Filtering**: livestreams and short-form videos are excluded when the guild's `content_filter` says
so (FR-040).

## Reconciliation sweep

Push alone is not trustworthy, so a low-frequency sweep re-checks state for all subscriptions.

It compares observed upstream state against the last-announced identifier recorded per subscription
and announces only genuinely new events. Anything older than the staleness threshold is dropped and
recorded, which is how FR-043's "no backlog burst after an outage" is satisfied — the sweep is
explicitly not a catch-up mechanism.

The sweep and the push path converge on the same deduplication anchors in the database, so the two
cannot produce a duplicate between them. Its frequency is bounded by the platforms' rate limits and
must leave headroom for push-triggered work; it is a safety net, not a second polling loop.

At V1's ceiling of 100 distinct identities of each kind, a full Twitch reconciliation is a single
`Get Streams` call costing one point of the 800-point minute bucket, so the sweep can run often
without meaningful cost. This is a consequence of choosing small ceilings, and it is the reason V1
need not tune the sweep interval carefully.
