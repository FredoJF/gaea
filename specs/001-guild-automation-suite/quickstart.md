# Quickstart: Validating the Guild Automation Suite

**Date**: 2026-09-16 · **Plan**: [plan.md](plan.md) · **Data model**: [data-model.md](data-model.md)

This is a validation guide: how to bring the bot up and prove each user story works end to end.
Implementation detail belongs in `tasks.md`; schema detail is in
[contracts/schema.sql](contracts/schema.sql).

## Prerequisites

All Constitution Check gates pass as of 2026-09-16. Both prior blockers are closed: the toolchain is
at 1.98.1 (latest stable), and the `tracing` activity window was corrected to 180 days in
constitution v1.1.1.

- Rust 1.98.1, pinned by `rust-toolchain.toml`.
- PostgreSQL 18.x reachable, with two roles: a privileged role for migrations and a DML-only role
  for the services (ADR-0004, and the constitution's privilege-isolation rule). A running instance
  is required for any test run, because `#[sqlx::test]` creates a fresh database per test against it
  (ADR-0010).
- A Discord application with a bot user. **The Members privileged intent must be enabled in the
  Developer Portal** — greetings cannot function without it, and nothing else in this feature needs
  a privileged intent.
- Bot invited with: View Channel, Send Messages, Embed Links, Manage Channels, Move Members,
  Connect. Not Administrator.
- A test guild you control, plus a second Discord account for join and voice testing.
- Secret files on disk; paths named in configuration. Never environment variables (ADR-0008).

## Setup

```bash
# 1. Verify the toolchain matches the pin. This should fail loudly if it does not.
rustc --version                       # expect 1.98.1

# 2. Apply the schema with the PRIVILEGED role.
cargo run --bin gaea-migrate -- --database-url-file /run/secrets/db_admin_url

# 3. Build with the gates the constitution requires.
cargo clippy --workspace --all-targets -- -D warnings
cargo doc --workspace --no-deps        # fails on any undocumented public item
cargo audit && cargo deny check

# 4. Configure a test guild (operator-side; the dashboard does not exist yet).
cargo run --bin gaea-admin -- --config ./config/dev.toml guild set-timezone <guild-id> Europe/Paris

# 5. Start the bot with the DML-only role.
cargo run --bin gaea-bot -- --config ./config/dev.toml
```

The bot must refuse to start — with an explanatory error, not a stack trace — when a required secret
is missing or malformed, or when the trusted-proxy configuration is contradictory. Verify this
deliberately by removing a secret file; a silent default here would be a Principle I failure.

## Validating each user story

Configuration is performed in the dashboard (spec 002) by guild owners, administrators and
managers. Until the dashboard exists, the operator configures through `gaea-admin` on the host
(ADR-0010) — which applies the same validation, so a configuration accepted here is one the
dashboard would also accept. Each scenario should be re-run through the dashboard once available.

### US1 — Greetings (P1)

1. Configure a greeting with a channel and a template using the member-mention placeholder.
2. Join with the second account. **Expect** the greeting within 5 seconds (SC-002).
3. Set the joining account's display name to contain `@everyone`, leave, rejoin. **Expect** the name
   rendered as inert text and no mass notification (FR-004, SC-007). This is a security test, not a
   cosmetic one.
4. Switch presentation to card. **Expect** a coloured card carrying the member's avatar. Repeat with
   an account that has no avatar — **expect** a card with no avatar, not a broken image (FR-012c).
5. Remove the bot's permission to post in the target channel, then join. **Expect** no message, a
   recorded failure, and an operator-readable reason (FR-007).
6. Join, leave and rejoin rapidly past the configured rate. **Expect** throttling that is recorded,
   not silently dropped (FR-015).

### US2 — Temporary voice channels (P2)

1. Designate a hub channel. Join it. **Expect** a channel created and the member moved into it
   within 3 seconds, and the member no longer in the hub (SC-003, FR-016b).
2. Leave. **Expect** deletion within the grace period, and within 30 seconds (SC-003).
3. Rejoin the hub while still owning a channel. **Expect** to be returned to the existing channel,
   not given a second (FR-016c).
4. Rename and set a limit on your own channel; attempt the same against another member's. **Expect**
   success then denial, with the denial revealing nothing about the other channel (FR-018).
5. Join and leave the hub repeatedly past the rate limit. **Expect** refusal, removal from the hub
   with a reason, and an audit entry (FR-019).
6. Delete the hub channel in Discord. **Expect** the feature reported misconfigured and no creation
   attempted (FR-020b).
7. Kill the bot with channels live, empty them, restart. **Expect** orphans reconciled and deleted
   (FR-021). This is the restart path SC-008 soaks for seven days.

### US3 — Scheduled messages (P3)

1. Schedule a one-time message two minutes out. **Expect** delivery within 60 seconds of the instant
   (SC-004).
2. Schedule a daily message; let it fire twice. **Expect** exactly one message per occurrence and a
   listing showing the next occurrence as a concrete date and time (FR-029).
3. Stop the bot across a scheduled instant; restart within 15 minutes. **Expect** delivery. Repeat
   with a restart after 15 minutes. **Expect** a recorded skip, and the schedule still active
   (FR-027).
4. **Daylight saving.** Do not wait for March. Set the guild timezone to one that observes
   transitions and run the domain-level replay that SC-004a requires — a full simulated year against
   `gaea-domain/schedule` with an injected clock. **Expect** exactly one firing per intended
   occurrence, including a local time that does not exist on the spring-forward day and one that
   occurs twice on the fall-back day (FR-023b, FR-023c). This test is the reason that logic is pure
   code with no database or gateway dependency.
5. Change the guild timezone. **Expect** existing schedules to keep their stated local time and show
   a recomputed next occurrence (FR-023d).
6. Delete the target channel, then let a schedule fire. **Expect** suspension with an
   operator-readable reason, not indefinite retry (FR-028).

### US4 — Twitch alerts (P4)

1. Subscribe to a streamer who is offline. Subscribe to a name that does not exist. **Expect** the
   second rejected with nothing stored (FR-033).
2. Have the streamer go live. **Expect** one alert within 2 minutes carrying title, category and
   link (SC-005, FR-034).
3. Have the stream drop and reconnect inside the window. **Expect** no second alert (FR-032).
4. Replay the same EventSub notification. **Expect** it acknowledged and discarded.
5. Block outbound access to Twitch for an hour, then restore. **Expect** no crash, no false alerts,
   and no backlog burst (SC-011, FR-043).
6. Subscribe two different guilds to the same streamer. **Expect** exactly one upstream EventSub
   subscription, and both guilds alerted from the single received event (FR-035b).
7. **Induce a revocation.** Make the callback fail repeatedly until Twitch revokes with
   `notification_failures_exceeded`, or delete the subscription upstream. **Expect** the upstream
   marked revoked with the stated reason, and an operator-visible fault — not a silent stop
   (FR-035e, SC-005b). This is the most likely way this feature dies quietly in production.
8. Restart the bot with upstream subscriptions already present. **Expect** recreation treated as
   success, and no guild left silently unsubscribed (FR-035g).
9. Send a callback with a forged signature, and a valid one with an old timestamp. **Expect** both
   rejected before any parsing or action (FR-035d).

### US5 — YouTube alerts (P5)

1. Subscribe to a channel with an existing back catalogue. **Expect** no alerts for anything
   published before subscription (FR-039) — the feed delivers the back catalogue on first push, so
   this is a real trap, not a theoretical one.
2. Publish a video. **Expect** one alert within 10 minutes (SC-005).
3. Edit the video's title. **Expect** no second alert (FR-038).
4. Publish a livestream and a short with both filters on. **Expect** no alerts (FR-040).
5. **Expire a WebSub lease deliberately** by suppressing renewal. **Expect** the reconciliation sweep
   to catch the gap and the failed renewal to appear as an operator-visible fault — not a log line
   nobody reads (FR-042c, SC-005b). This is the silent-failure mode the sweep exists for.
6. Confirm the renewal schedule is derived from the `lease_seconds` the hub returned, not from a
   constant. Subscribe and inspect the stored expiry against the confirmation (FR-042c).
7. Subscribe two guilds to the same YouTube channel. **Expect** one upstream subscription and both
   guilds alerted (FR-042d).

## Cross-cutting checks

| Check | Expectation | Requirement |
|---|---|---|
| Two bot instances started | Second refuses to start; no duplicated greetings | Single-shard singleton |
| Bot removed from a guild | No automated action of any kind during dormancy | FR-009a, SC-013 |
| Bot re-added within 30 days | Configuration restored **and announced**, not silently reinstated | FR-009b |
| 30 days elapsed while bot offline | Deletion performed on next start | FR-009c, SC-014 |
| Guild at 500 channels, member joins hub | Refusal with reason, no partial channel | FR-020 |
| Logs inspected after a full run | No secret, token or message content anywhere | Principle VI |
| Metrics endpoint scraped | Gateway state, event latency, error rate, rate-limit consumption present; no guild-identifying labels | Principle VI, ADR-0009 |
| One guild's external dependency fails | Other guilds unaffected | SC-010, FR-008 |

## Load validation

SC-005a's target for this version is 25 guilds holding at most 100 distinct Twitch broadcasters and
100 distinct YouTube channels between them. At that size the external budgets are effectively
unused: a full Twitch reconciliation is a single `Get Streams` call costing one point of an
800-point minute bucket, and the YouTube Data API is not touched at all.

No load *modelling* is required for V1 — the ceilings were chosen precisely so that none is. A smoke
check at the target size is still run, so SC-005a and SC-009 are verified rather than merely
asserted; see the scale task in [tasks.md](tasks.md). What **is** required before those ceilings are
raised is confirming Twitch's application-wide total-cost ceiling, which V1 deliberately does not
depend on. See [research.md](research.md).

The behavioural tests above are a different matter and are not optional at any scale. A revoked
subscription and a lapsed lease fail identically with 25 guilds and with 1,000, and neither
announces itself.
