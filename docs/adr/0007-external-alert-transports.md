# ADR-0007: Twitch and YouTube Alert Transports

**Status**: Accepted · **Date**: 2026-09-16

## Context

SC-005 (001) requires 95% of Twitch alerts within 2 minutes of a broadcast starting and 95% of
YouTube alerts within 10 minutes of publication. SC-005a requires those to hold at 1,000 guilds each
holding 25 Twitch and 25 YouTube subscriptions. FR-032 and FR-038 require at most one alert per
broadcast and per video. FR-043 forbids a backlog burst after an outage.

This is the one decision that determines whether those targets are reachable at all.

### Measured constraints (verified 2026-09-16)

- **Twitch EventSub over WebSocket**: each connection may hold at most 300 enabled subscriptions,
  and `max_total_cost` is **10** across all subscriptions (Twitch Developer Docs, *Handling
  WebSocket Events*). `stream.online` on an arbitrary broadcaster does not require user
  authorization and therefore costs 1, so WebSocket transport caps the whole deployment at roughly
  **ten streamers**. This is decisive and rules WebSocket out.
- **Twitch EventSub over webhook**: a substantially higher total-cost ceiling with an app access
  token, requiring a public HTTPS callback — which this deployment has, since the dashboard is
  already public (FR-040, 002). The exact ceiling must be re-confirmed against the current
  *Subscription limits* documentation before implementation.
- **YouTube**: the channel feed at `youtube.com/feeds/videos.xml?channel_id=` responds without an
  API key (verified, HTTP 200), and the WebSub hub at `pubsubhubbub.appspot.com` is reachable
  (verified, HTTP 200). The YouTube Data API v3 default quota is **10,000 units per day** across all
  endpoints, which makes API polling untenable at this scale.

## Decision

**Push for both platforms, plus a slow periodic reconciliation sweep.**

- Twitch: EventSub `stream.online` subscriptions delivered by **webhook** to the public host.
- YouTube: **WebSub** subscriptions to the channel feed, delivered to the public host.
- A low-frequency sweep re-checks state for all subscriptions to catch missed pushes and lapsed
  WebSub leases.

## Rationale

Push is the only transport that meets the latency targets within the platforms' budgets. Polling
1,000 guilds' worth of subscriptions frequently enough for a 2-minute target would breach Twitch's
rate limits and YouTube's daily quota by a wide margin.

The reconciliation sweep exists because push alone is not trustworthy. WebSub leases expire and must
be renewed; a renewal that silently fails means a channel's uploads are never announced again, with
nothing detecting it. Individual callbacks are dropped. Without reconciliation, the failure mode is
an alert that simply never fires — invisible to everyone including the operator. The sweep is what
makes FR-043's "no backlog burst" and the duplicate-suppression requirements testable: it compares
observed state against the last-announced identifier recorded per subscription and announces only
genuinely new events, dropping anything past the staleness threshold.

Deduplication is anchored in the database, not in memory: the last-announced broadcast identifier on
each Stream Subscription and the recently-announced video identifiers on each Video Subscription
(001, Key Entities). This is what makes at-most-once hold across restarts and across the push and
sweep paths converging on the same event.

## Alternatives Considered

- **Push only** — lowest latency and quota use. Rejected: a lapsed lease or dropped callback means a
  silent permanent failure.
- **Poll both platforms** — no public callback needed. Rejected on the measured quota numbers above.
- **EventSub over WebSocket** — rejected on the `max_total_cost` of 10.
- **Push Twitch, poll YouTube RSS** — avoids WebSub lease renewal. Rejected: RSS polling cost grows
  linearly with distinct channels followed, and the 10-minute target degrades as the deployment
  grows, which is exactly the scaling property FR-042b (001) exists to prevent.

## Consequences

- The web process gains two public callback endpoints. Both are unauthenticated by nature and must
  verify their platform's signature before any parsing or side effect, and must be rate-limited
  independently of the dashboard's own traffic.
- Twitch requires callback verification challenges to be answered; WebSub requires subscription
  confirmation and periodic lease renewal. Lease renewal is a scheduled job whose failure must be
  visible in the activity record (FR-025, 002), not silent.
- Callbacks arrive at the web process but the work belongs to the alert pipeline. Handing off
  through the database keeps ADR-0003's independence intact, and is the seam along which a third
  process can later be split.
- Because alerts depend on the public host, a sustained dashboard outage delays alerts. The
  reconciliation sweep bounds the damage: alerts resume on recovery without a burst.
- The exact Twitch webhook cost ceiling and the WebSub lease duration must be confirmed against
  current documentation and recorded before implementation; both are inputs to FR-042b's
  deployment-wide subscription ceiling.
