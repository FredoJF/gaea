# Phase 0 Research: Guild Automation Suite

**Date**: 2026-09-16 · **Feature**: [spec.md](spec.md) · **Plan**: [plan.md](plan.md)

All technology selections were made and recorded before this plan, in
[ADR-0001 through ADR-0009](../../docs/adr/README.md). This document consolidates those decisions,
records the measurements taken while writing this plan, and resolves the remaining unknowns.

## Decisions carried in from the ADRs

| Decision | Choice | Record |
|---|---|---|
| Language, runtime, datastore | Rust · Tokio · Twilight · Serde · PostgreSQL | [ADR-0001](../../docs/adr/0001-language-runtime-and-datastore.md) |
| Pre-1.0 dependency policy | Six conditions; constitution amended to v1.1.0 | [ADR-0002](../../docs/adr/0002-pre-1.0-dependency-policy.md) |
| Process topology | Two binaries, one database; interactions over the gateway | [ADR-0003](../../docs/adr/0003-process-topology-and-interaction-transport.md) |
| Data access and migrations | SQLx compile-time-checked queries; separate migration binary | [ADR-0004](../../docs/adr/0004-data-access-and-migrations.md) |
| External alert transports | EventSub webhook + WebSub push, plus a reconciliation sweep | [ADR-0007](../../docs/adr/0007-external-alert-transports.md) |
| Secrets | File-mounted, read at startup | [ADR-0008](../../docs/adr/0008-secrets-and-configuration.md) |
| Observability | `tracing` for logs and spans; Prometheus scrape for metrics | [ADR-0009](../../docs/adr/0009-observability.md) |

## New measurements taken for this plan (2026-09-16)

### Dependency activity against amended Principle III condition (b)

| Dependency | Last release | Last commit | Days since commit | Condition (b) |
|---|---|---|---|---|
| Twilight | 2025-12-13 | 2026-08-30 | 17 | PASS |
| Axum | 2026-04-14 | 2026-09-15 | 1 | PASS |
| tracing | 2025-12-18 | 2026-05-30 | **108** | **FAIL** |

**Decision**: `tracing` is retained in the design, and the condition (b) failure is escalated rather
than absorbed. It appears in the plan's Constitution Check as a gate failure and in Complexity
Tracking with two proposed resolutions.

**Rationale**: The honest reading is that 90 days is a tight window for an infrastructure crate that
has reached stability — `tracing` is not drifting, it is finished enough not to need weekly commits.
But the condition was adopted two days ago precisely to stop "everyone uses it" from substituting
for evidence, and quietly making an exception on its first application would render it decorative.
The window should be widened deliberately or an exception recorded deliberately; either is
defensible, silently passing is not.

**Alternatives considered**: Implementing logging in-house — rejected, it would mean reimplementing
span propagation, which is the exact mechanism Principle VI's correlation requirement depends on.
Using `log` instead — rejected, no span model, so a correlation identifier would have to be threaded
by hand through every function signature.

### Axum release cadence

**Finding**: Axum's last release is 2026-04-14 (5 months) but its repository was committed to
2026-09-15 — one day before this plan.

**Decision**: The cadence concern recorded in ADR-0005 is downgraded. A slow release train over an
actively developed repository is a different risk from dormancy, and condition (b) measures commits
for exactly this reason.

### Twitch EventSub transport — confirmed decisive measurement

**Finding**: EventSub over WebSocket permits at most 300 enabled subscriptions per connection with a
`max_total_cost` of **10** across all subscriptions (Twitch Developer Docs, *Handling WebSocket
Events*, retrieved 2026-09-16). `stream.online` on an arbitrary broadcaster requires no user
authorization and therefore costs 1.

**Decision**: WebSocket transport is eliminated. It would cap the entire deployment at roughly ten
streamers against a target of 1,000 guilds × 25 subscriptions. Webhook transport, per
[ADR-0007](../../docs/adr/0007-external-alert-transports.md).

**Open**: the exact webhook total-cost ceiling with an app access token could not be extracted from
the rendered documentation and **must be confirmed before implementation**. It is a direct input to
FR-042b's deployment-wide subscription ceiling. Until confirmed, FR-042b's threshold is a
configurable value with no defensible default.

### YouTube transport

**Finding**: the channel feed at `youtube.com/feeds/videos.xml?channel_id=…` returns HTTP 200 with
no API key, and the WebSub hub at `pubsubhubbub.appspot.com` returns HTTP 200 (both verified
2026-09-16). YouTube Data API v3 provides 10,000 units per day across all endpoints.

**Decision**: WebSub push against the channel feed. The Data API is not used, so no API quota
applies and no API key is needed for the alert path.

**Open**: the WebSub lease duration granted by the hub must be measured at implementation time, as
it sets the renewal schedule. A lease that lapses without renewal produces a silent permanent
failure — a channel whose uploads are simply never announced — which is the specific failure the
reconciliation sweep exists to catch.

## Unknowns resolved for this plan

### Gateway intents

**Decision**: `GUILDS` and `GUILD_VOICE_STATES` (both non-privileged), plus `GUILD_MEMBERS`
(privileged). `MESSAGE_CONTENT` and `GUILD_PRESENCES` are not requested.

**Rationale**: `GUILD_MEMBERS` is the only privileged intent and is required solely for member-join
events, without which FR-011's greeting cannot exist — the justification Principle I demands in
writing. `GUILD_VOICE_STATES` is needed for hub-join detection (FR-016) and is not privileged.
Nothing in this specification reads message content, so not holding that capability is preferable to
holding and not using it.

**Consequence**: the operator must enable the Members intent in the Discord Developer Portal.
Greetings cannot function without it, and the dashboard must say so rather than failing silently
(FR-025 of 002).

### Discord permissions requested at install

**Decision**: View Channel, Send Messages, Embed Links, Manage Channels, Move Members, Connect.

**Rationale**: Embed Links is required by the card presentation (FR-012a). Manage Channels and Move
Members are required by FR-016. Administrator, Manage Guild, Kick, and Ban are not requested — the
bot performs no moderation in this version, and FR-012 of 002 forbids the bot's permissions from
amplifying a user's own authority.

### Sharding

**Decision**: a single gateway shard; the bot process is a singleton.

**Rationale**: Discord requires one shard per 2,500 guilds (Discord Developer Docs, *Gateway →
Sharding*); the SC-009 target is 1,000 guilds.

**Consequence**: running two bot instances would duplicate every event — every greeting posted
twice. This must be prevented operationally and guarded in code by an advisory lock taken at
startup, because the exactly-once guarantees in FR-014, FR-026, FR-032 and FR-038 all assume a
single consumer of gateway events.

### Exactly-once scheduled delivery

**Decision**: a claim-based queue in PostgreSQL using `SELECT … FOR UPDATE SKIP LOCKED`, with the
last-delivered occurrence recorded on each schedule row.

**Rationale**: FR-026 requires exactly-once across restarts, redeployments and concurrent instances.
`SKIP LOCKED` is the documented idiom (PostgreSQL docs, *SELECT → The Locking Clause*) and lets a
claim, a delivery record and a state update commit in one transaction. An in-memory timer would lose
its state on restart and could not coordinate across processes.

**Alternatives considered**: an external queue broker — rejected as an additional datastore for the
operator to run when PostgreSQL already provides the primitive. An in-process timer wheel —
rejected: it cannot survive a restart, which FR-004's 15-minute catch-up rule requires.

### Daylight-saving arithmetic

**Decision**: occurrences are computed in the guild's IANA timezone at the moment they are needed,
never precomputed at schedule creation. A non-existent local time resolves to the first instant the
local clock reaches or passes it (FR-023b); an ambiguous one resolves to the first of its two
occurrences (FR-023c).

**Rationale**: resolving at computation time means a jurisdiction changing its rules is handled by
updating tz data rather than by rewriting stored timestamps. The two rules are stated as
requirements because these are the two days a year when a scheduling bug silently drops or doubles a
message.

**Consequence**: this logic lives in `gaea-domain` as pure code with an injected clock, so SC-004a
can replay a full simulated year against a transition-observing timezone in milliseconds rather than
waiting for March.

### Discord rate limiting

**Decision**: a proactive client-side limiter honouring per-route bucket headers
(`X-RateLimit-Bucket`, `-Remaining`, `-Reset-After`) and the 50-requests-per-second global limit,
with a 429 response treated and logged as a defect in the limiter itself.

**Rationale**: the constitution requires exactly this, and the 10,000-invalid-requests-per-10-minutes
threshold that triggers a Cloudflare ban makes reactive limiting unacceptable — a bot that learns
its limits by hitting them can lose access for every guild at once.

**Consequence**: rate-limit consumption is a Principle VI metric, because a 429 is only detectable
as a defect if headroom is measured continuously.

### Guild dormancy

**Decision**: removal marks a guild dormant with a deletion date 30 days out; a scheduled sweep
performs the deletion; re-adding within the window clears the mark and announces the restoration.

**Rationale**: FR-009 through FR-009c. FR-009c requires the deletion to be unconditional and to
survive the bot being offline on the day it falls due, so the sweep must reconcile against a stored
date rather than firing a timer.

**Consequence**: every query serving automated behaviour must exclude dormant guilds. FR-009a is not
a filter applied in one place — it is an invariant, and the cleanest enforcement is to make dormancy
a condition of the repository methods the feature runners use, so that forgetting it is not possible
rather than merely discouraged.
