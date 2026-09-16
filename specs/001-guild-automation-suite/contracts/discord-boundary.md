# Contract: Internal Discord Boundary

**Required by**: amended Principle III condition (d) — a pre-1.0 dependency must be isolated behind
a project-owned boundary such that it can be replaced or forked without touching domain logic.
Recorded in [ADR-0002](../../../docs/adr/0002-pre-1.0-dependency-policy.md).

This is the single most important structural contract in the feature. It is what makes Twilight
replaceable, and — more immediately valuable — what makes every deny-path test in Principle V
runnable without a live gateway.

## Rule

`gaea-discord` is the only crate permitted to name a Twilight type. No Twilight type may appear in
`gaea-domain`, `gaea-store`, or any binary's feature logic. This is enforced mechanically, not by
review: Twilight appears as a dependency of exactly one crate in the workspace manifest, so a
violation is a compile error.

## Operations the boundary exposes

Only what this feature actually needs. Every addition requires justification, because each one is
surface that a replacement implementation must also provide.

| Operation | Serves |
|---|---|
| `send_message(channel, rendered)` | FR-011, FR-025, FR-031, FR-037 |
| `send_card(channel, rendered, colour, avatar)` | FR-012a |
| `create_voice_channel(guild, category, name)` | FR-016 |
| `move_member(guild, member, channel)` | FR-016 |
| `delete_channel(channel)` | FR-017, FR-020a |
| `modify_channel(channel, name, limit, permissions)` | FR-018 |
| `disconnect_member(guild, member)` | FR-016b |
| `list_channels(guild)` / `list_roles(guild)` | Reconciliation, and 002's pickers |
| `guild_channel_count(guild)` | FR-020 |
| `member_avatar(member)` | FR-012a, FR-012c |
| `events()` — a stream of `GuildEvent` | The gateway loop |

## Types crossing the boundary

Every type in these signatures is defined by `gaea-domain`. Identifiers are newtypes
(`GuildId`, `ChannelId`, `MemberId`) rather than bare integers, so the compiler rejects passing a
channel where a guild is expected.

`GuildEvent` is an enum of exactly what this feature consumes — `MemberJoined`, `VoiceStateChanged`,
`ChannelDeleted`, `GuildRemoved`, `GuildAdded`, `InteractionReceived`, `Connected`, `Disconnected`.
Anything Discord sends that is not one of these is discarded at the boundary and never reaches
domain logic.

## Outbound message safety

Every send path suppresses mentions via `allowed_mentions` rather than by escaping the message text,
per FR-004. This is a property of the boundary, not of each caller: there is no method that sends a
message without it, so FR-004 cannot be violated by forgetting.

Where an operator has been explicitly authorized and has opted in to a mass notification, that is a
distinct method with a distinct name, so the dangerous path is visible at every call site and in
every diff.

## Rate limiting

The boundary owns the proactive limiter — per-route buckets and the 50-requests-per-second global
limit. Callers do not think about rate limits; they await a send. A 429 reaching the limiter is
logged as a defect in the limiter, per the constitution, and surfaces as a Principle VI metric.

## Test double

`gaea-discord` ships an in-memory implementation recording every call and returning scripted
outcomes, including the failure modes Principle V requires contract tests for: HTTP 429 with
`retry_after`, gateway resume, invalid session, missing permission, deleted channel, and guild at
the 500-channel limit. Domain and integration tests use it exclusively; no test opens a socket to
Discord.
