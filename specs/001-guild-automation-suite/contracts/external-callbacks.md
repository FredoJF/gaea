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
— not one per guild subscription. Many guilds following one streamer cost approximately what one
guild costs, which is why FR-042b's deployment ceiling counts distinct identities.

**Verification**: HMAC signature over the message id, timestamp, and raw body, compared in constant
time. A timestamp outside a narrow window is rejected as a replay. Verification precedes
deserialization.

**Message types**: `webhook_callback_verification` (echo the challenge), `notification`, and
`revocation` (which must mark the subscription broken and surface it to the operator, never be
ignored).

**Deduplication**: Twitch may redeliver. The message id is recorded; a repeat is acknowledged and
discarded. Independently, `last_announced_broadcast_id` on each subscription suppresses a second
alert for the same broadcast, including across a reconnect within the FR-032 window.

**Response discipline**: acknowledge quickly and do the work asynchronously. A slow handler causes
retries, and retries at scale look like an outage.

## YouTube WebSub

**Hub**: `pubsubhubbub.appspot.com`. **Topic**: the channel feed at
`youtube.com/feeds/videos.xml?channel_id=…`, one subscription per distinct channel followed.

**Verification**: the hub performs a subscribe/unsubscribe confirmation challenge that must be
echoed. Content notifications are verified against the shared secret supplied at subscription time.

**Leases expire.** This is the failure mode that matters: a lease that lapses without renewal
produces no error anywhere, it simply means that channel's uploads are never announced again.
`lease_expires_at` is stored per subscription, renewal is scheduled ahead of it, and a failed
renewal is recorded as an operator-visible fault (FR-025 of 002) rather than a log line nobody reads.

**Deduplication**: the feed redelivers on edits. FR-038 requires at most one alert per video
regardless, enforced by uniqueness on announced video identifiers. FR-039 requires nothing published
before `subscribed_at` to be announced — relevant because the feed carries a back catalogue on first
delivery.

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
