# Phase 1 Data Model: Guild Automation Suite

**Date**: 2026-09-16 · **Feature**: [spec.md](spec.md) · **Schema**: [contracts/schema.sql](contracts/schema.sql)

Entities are those named in the specification's Key Entities section. Every table is rooted at a
guild and cascades from it, which is how FR-001's cross-guild isolation is enforced by the schema
rather than by application discipline.

## Conventions

- Discord snowflakes are stored as `BIGINT`. They are 64-bit unsigned in Discord's model but fit
  signed 64-bit for all realistic timestamps; storing them as text would lose ordering.
- Every timestamp recording *when something happened* is `TIMESTAMPTZ`. Every value recording *a
  local time a user chose* is stored as a `TIME` plus a separate IANA zone identifier — never as a
  pre-resolved instant, per the ADR-0007 and research.md reasoning on daylight saving.
- Soft state that must not act (dormancy) is expressed as a nullable column on `guild`, and every
  repository method serving automated behaviour filters on it. See *Dormancy* below.

## Entities

### guild

The root of all configuration. One row per Discord guild the bot has been added to.

| Field | Type | Notes |
|---|---|---|
| `id` | BIGINT PK | Discord guild snowflake |
| `timezone` | TEXT NOT NULL | IANA zone identifier; required before a schedule can exist (FR-023a) |
| `removed_at` | TIMESTAMPTZ NULL | Set when the bot is removed; NULL means active |
| `purge_after` | TIMESTAMPTZ NULL | `removed_at + 30 days` (FR-009). Unconditional (FR-009c) |
| `max_greetings_per_minute` | INTEGER NOT NULL | Per-guild throttle (FR-015) |
| `max_messages_per_minute` | INTEGER NOT NULL | Outbound ceiling (FR-010) |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

**Validation**: `timezone` must resolve against the IANA database; an unknown zone is rejected at
write time, not at delivery time.

**State transitions**: `active → dormant` on removal (sets `removed_at`, `purge_after`);
`dormant → active` on re-add within the window (clears both, announces restoration per FR-009b);
`dormant → deleted` when `purge_after` passes (row deleted, cascading to everything below).

### welcome_setting

One row per guild. Holds FR-011 through FR-015 and FR-012a.

| Field | Type | Notes |
|---|---|---|
| `guild_id` | BIGINT PK FK → guild | |
| `enabled` | BOOLEAN NOT NULL | Disabling retains the template (FR-006) |
| `channel_id` | BIGINT NOT NULL | Destination |
| `template` | TEXT NOT NULL | Validated at write time (FR-005) |
| `presentation` | ENUM('plain','card') NOT NULL | Exactly two (FR-012a) |
| `card_colour` | INTEGER NULL | Only meaningful when `presentation = 'card'` |

**Validation**: the template must reference only known placeholders and must render within the
platform limit for its presentation under worst-case substitution (FR-005, FR-012d). No field may
contain an image address (FR-012b) — enforced by validation, since the schema has no column for one.

### temporary_voice_setting

One row per guild. The hub-join model from FR-016.

| Field | Type | Notes |
|---|---|---|
| `guild_id` | BIGINT PK FK → guild | |
| `enabled` | BOOLEAN NOT NULL | |
| `hub_channel_id` | BIGINT NOT NULL | Joining this creates a channel (FR-016) |
| `category_id` | BIGINT NULL | Where created channels are placed |
| `name_pattern` | TEXT NOT NULL | Sanitized to 100 chars and the permitted set (FR-022) |
| `empty_grace_seconds` | INTEGER NOT NULL | FR-017 |
| `max_per_member` | INTEGER NOT NULL | FR-019 |
| `creations_per_window` / `window_seconds` | INTEGER NOT NULL | FR-019 |

**Validation**: invalid when `hub_channel_id` no longer exists or the bot cannot act on it; the
feature then reports misconfigured and attempts no creation (FR-020b).

### temporary_voice_channel

Live state for a channel the bot created. Transient — exists only while the channel does.

| Field | Type | Notes |
|---|---|---|
| `channel_id` | BIGINT PK | The created Discord channel |
| `guild_id` | BIGINT FK → guild | |
| `owner_id` | BIGINT NOT NULL | Controls it (FR-018) |
| `created_at` | TIMESTAMPTZ NOT NULL | |
| `empty_since` | TIMESTAMPTZ NULL | NULL when occupied; drives FR-017 deletion |

**Uniqueness**: a partial unique index on `(guild_id, owner_id)` enforces FR-016c — a member
rejoining the hub while owning a channel is returned to it rather than given a second.

**State transitions**: `created → occupied → empty (empty_since set) → deleted`. Reoccupation clears
`empty_since`. Restart reconciliation (FR-021) compares this table against live channels and deletes
orphans. Ownership transfer on owner departure updates `owner_id` (FR-018, scenario 7).

### scheduled_message

Many per guild. Holds FR-023 through FR-029.

| Field | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `guild_id` | BIGINT FK → guild | |
| `channel_id` | BIGINT NOT NULL | |
| `content` | TEXT NOT NULL | |
| `recurrence` | ENUM('once','daily','weekly') NOT NULL | No other pattern (FR-023) |
| `local_time` | TIME NOT NULL | Interpreted in the guild's zone, never pre-resolved |
| `weekday` | SMALLINT NULL | Required when `recurrence = 'weekly'` |
| `fire_date` | DATE NULL | Required when `recurrence = 'once'` |
| `next_occurrence` | TIMESTAMPTZ NOT NULL | Computed; the queue index |
| `last_delivered_occurrence` | TIMESTAMPTZ NULL | **The exactly-once anchor (FR-026)** |
| `state` | ENUM('active','suspended') NOT NULL | Suspended on delivery failure (FR-028) |
| `suspend_reason` | TEXT NULL | Surfaced to the operator (FR-028, FR-025 of 002) |

**Why `last_delivered_occurrence` is the load-bearing column**: FR-026 requires exactly-once across
restarts, redeployments and concurrent instances. Delivery claims a row with
`FOR UPDATE SKIP LOCKED`, and the same transaction that sends sets this column. A re-evaluation of
an instant already recorded here is a no-op, which is what FR-026's scenario 6 demands.

**Validation**: `weekday` present iff weekly; `fire_date` present iff once. A guild timezone must
exist (FR-023a). Changing the guild timezone preserves `local_time` and recomputes
`next_occurrence` (FR-023d).

### stream_subscription / video_subscription

Many per guild, ceilinged at 25 each (FR-035a, FR-042a).

Shared fields: `id` UUID PK · `guild_id` FK · `channel_id` (Discord destination) · `template` ·
`created_at`.

| Twitch-specific | Notes |
|---|---|
| `broadcaster_id` TEXT NOT NULL | Validated at subscription time (FR-033) |
| `last_announced_broadcast_id` TEXT NULL | Duplicate suppression (FR-032) |
| `last_announced_at` TIMESTAMPTZ NULL | Supports the reconnect window in FR-032 |

| YouTube-specific | Notes |
|---|---|
| `youtube_channel_id` TEXT NOT NULL | Validated at subscription time (FR-041) |
| `subscribed_at` TIMESTAMPTZ NOT NULL | **Nothing published before this is announced (FR-039)** |
| `content_filter` | Excludes livestreams and shorts (FR-040) |
| `lease_expires_at` TIMESTAMPTZ NULL | WebSub renewal deadline; a lapse here is a silent failure |

Announced video identifiers live in a child table rather than an array, so FR-038's "at most one
alert per video, including after edits" is a uniqueness constraint rather than a search.

**Ceilings**: FR-035a and FR-042a are per-guild counts enforced at write time. FR-042b's
deployment-wide ceiling is enforced against the count of *distinct* upstream identities, because
many guilds following one streamer costs approximately what one guild costs.

### delivery_record

Append-only. Serves both FR-003's audit obligation and the exactly-once guarantees.

| Field | Type | Notes |
|---|---|---|
| `id` | BIGSERIAL PK | |
| `guild_id` | BIGINT FK → guild | |
| `kind` | ENUM | greeting · scheduled · stream_alert · video_alert · voice_created · config_change |
| `subject` | TEXT NOT NULL | Join event, occurrence instant, broadcast id, video id |
| `actor_id` | BIGINT NULL | NULL for automated actions |
| `outcome` | ENUM('delivered','skipped','suppressed','failed') | |
| `reason` | TEXT NULL | Operator-actionable language (FR-025 of 002), never an error code |
| `occurred_at` | TIMESTAMPTZ NOT NULL | |

**Uniqueness**: `(guild_id, kind, subject)` unique where `outcome = 'delivered'` — this is what makes
"exactly once" a database constraint rather than an application hope, across greetings, scheduled
instants, broadcasts and videos alike.

**Retention**: 90 days by default, operator-configurable (FR-049 of 002), and deleted with the guild
on purge (FR-051 of 002).

## Cross-cutting invariants

**Dormancy (FR-009a)**. A dormant guild must perform no automated action. This is enforced by making
every repository method that feeds a feature runner filter `removed_at IS NULL`, so that omitting
the check is not possible rather than merely discouraged. A stored subscription for a departed guild
must not continue consuming external quota.

**Guild isolation (FR-001)**. Every table cascades from `guild`. No query serving one guild may
reference another; cross-guild reads exist only in deployment-wide aggregate counts, which return
counts and never rows.

**Rate ceilings (FR-010, FR-015, FR-019)**. Counters are evaluated against `delivery_record` within
a window rather than held in memory, so a restart cannot reset a guild's consumption and let it
exceed its ceiling.
