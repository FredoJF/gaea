---

description: "Task list for the Guild Automation Suite (spec 001)"
---

# Tasks: Guild Automation Suite (v1)

**Input**: Design documents from `/specs/001-guild-automation-suite/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md),
[data-model.md](data-model.md), [contracts/](contracts/)

**Tests**: Test tasks are included and are **not optional**. Principle V of the constitution
requires tests to precede implementation for every security control, requires allow-path *and*
deny-path coverage for every authorization check and validator, and requires contract tests for the
documented Discord failure modes.

**Organization**: Grouped by user story so each can be implemented, tested and demonstrated
independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on incomplete work)
- **[Story]**: Which user story the task serves (US1–US5)
- Every task names an exact path

## Path Conventions

Cargo workspace per [plan.md](plan.md) → Project Structure. Library crates under `crates/`,
binaries under `bins/`, cross-crate tests under `tests/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project skeleton and the pins Principle IV requires.

- [ ] T001 Create Cargo workspace manifest at `Cargo.toml` listing members `crates/gaea-domain`, `crates/gaea-discord`, `crates/gaea-store`, `crates/gaea-observability`, `crates/gaea-config`, `bins/gaea-bot`, `bins/gaea-migrate`, `bins/gaea-admin`, `bins/gaea-web`
- [ ] T002 Pin the toolchain in `rust-toolchain.toml` to `1.98.1` with components `rustfmt`, `clippy` — asserted rather than merely current on one machine
- [ ] T003 [P] Create `crates/gaea-domain/Cargo.toml` and `src/lib.rs` with `#![deny(missing_docs)]` and `#![forbid(unsafe_code)]`
- [ ] T004 [P] Create `crates/gaea-discord/Cargo.toml` and `src/lib.rs` with `#![deny(missing_docs)]`; this is the ONLY crate permitted to depend on Twilight
- [ ] T005 [P] Create `crates/gaea-store/Cargo.toml` and `src/lib.rs` with `#![deny(missing_docs)]`; the only crate depending on SQLx
- [ ] T006 [P] Create `crates/gaea-observability/Cargo.toml` and `src/lib.rs` with `#![deny(missing_docs)]`
- [ ] T007 [P] Create `crates/gaea-config/Cargo.toml` and `src/lib.rs` with `#![deny(missing_docs)]`
- [ ] T008 [P] Create binary skeletons `bins/gaea-bot/src/main.rs`, `bins/gaea-migrate/src/main.rs`, `bins/gaea-admin/src/main.rs` with their `Cargo.toml` files
- [ ] T009 Pin every dependency at an exact version in `Cargo.toml` under `[workspace.dependencies]` — tokio 1.53.1, twilight-gateway/-http/-model 0.17.1, serde 1.0.229, sqlx 0.9.0, tracing 0.1.44 — and commit `Cargo.lock`. Do NOT depend on `twilight-cache-inmemory`
- [ ] T010 [P] Configure lints in `Cargo.toml` `[workspace.lints]`: deny `clippy::unwrap_used`, `clippy::expect_used`, `clippy::panic`, `clippy::indexing_slicing`, and warnings-as-errors
- [ ] T011 [P] Create `deny.toml` configuring `cargo deny` for allowed licences (MIT, Apache-2.0, ISC, BSD-3-Clause) and duplicate-dependency detection, noting Gaea itself is AGPL-3.0
- [ ] T012 [P] Create `rustfmt.toml` and `.gitignore` covering `target/`, secret files, and `.env`

**Checkpoint**: `cargo build --workspace` succeeds with zero warnings.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The gates that make the constitution enforceable, plus the shared substrate every user
story needs.

**⚠️ CRITICAL**: No user story work begins until this phase completes.

### CI gates (Principles II, IV, V)

- [ ] T013 Create `.github/workflows/ci.yml` running on push and pull request, with a PostgreSQL 18 service container and both database roles (privileged for migrations, DML-only for tests)
- [ ] T014 Add a CI job to `.github/workflows/ci.yml` running `cargo clippy --workspace --all-targets -- -D warnings` — build fails on any warning (Principle V)
- [ ] T015 [P] Add a CI job to `.github/workflows/ci.yml` running `cargo doc --workspace --no-deps` so a missing doc comment on a public item fails the build (Principle II)
- [ ] T016 [P] Add a first-party SAST job to `.github/workflows/ci.yml` (CodeQL for Rust, or an equivalent static analyser) blocking merge on any finding at CVSS v4.0 base >= 7.0. Principle I requires SAST over first-party code, which `cargo audit` and `cargo deny` do not provide — they scan dependencies. Clippy is a linter, not a security analyser
- [ ] T017 [P] Add a CI job to `.github/workflows/ci.yml` running `cargo audit` against RustSec and `cargo deny check`, blocking merge on any advisory (Principle I, IV)
- [ ] T018 [P] Create `.github/workflows/staleness.yml` asserting no pinned dependency is more than 30 days behind its latest stable release, AND that no pin is younger than 72 hours unless it fixes an advisory — the cooldown is the detection window for a compromised publish, the CVE-2024-3094 shape. Fail immediately on any advisory (Principle IV)
- [ ] T019 [P] Add secret scanning over diff and history to `.github/workflows/ci.yml` (Principle I)
- [ ] T020 [P] Add SBOM generation in SPDX or CycloneDX format to a release workflow at `.github/workflows/release.yml` (Principle IV, PS.3.2)
- [ ] T021 [P] Create `./Containerfile` and `./compose.yml` running as a non-root user with a read-only root filesystem and `no-new-privileges`, per the constitution's Security and Platform Constraints

### Configuration and secrets (ADR-0008)

- [ ] T022 Write failing tests in `crates/gaea-config/src/lib.rs` for startup validation: a missing secret file, a malformed secret, and contradictory configuration MUST each refuse startup with an explanatory error, never a silent default
- [ ] T023 Implement file-mounted secret loading in `crates/gaea-config/src/secrets.rs` reading each secret once at startup from a path named in configuration; environment variables MUST NOT carry secret material in any build profile
- [ ] T024 Implement a `Secret` type in `crates/gaea-config/src/secret_type.rs` that does NOT implement `Display` or `Debug`, so a secret cannot reach a log through an ordinary formatting call (Principle VI)
- [ ] T025 Implement per-process secret scoping in `crates/gaea-config/src/scope.rs`: only the bot process may load the Discord bot token; only the web process may load the OAuth2 client secret and platform callback secrets (ADR-0008)

### Observability (Principle VI, ADR-0009)

- [ ] T026 [P] Implement the `tracing` subscriber facade in `crates/gaea-observability/src/logging.rs` emitting structured records with a correlation identifier propagated by span
- [ ] T027 [P] Implement redaction types in `crates/gaea-observability/src/redaction.rs`: identifiers that MAY be logged and content that MUST NOT are distinct types, so Principle VI's redaction cannot be violated by an ordinary formatting call
- [ ] T028 [P] Implement the Prometheus metrics registry and exporter in `crates/gaea-observability/src/metrics.rs` covering gateway connection state, event processing latency, command error rate, and Discord rate-limit consumption. Metric labels MUST NOT carry guild-identifying data
- [ ] T029 [P] Implement health and readiness endpoints in `crates/gaea-observability/src/health.rs`; bot readiness means a live gateway connection, not merely a running process

### Data layer (ADR-0004, [contracts/schema.sql](contracts/schema.sql))

- [ ] T030 Create the initial migration at `crates/gaea-store/migrations/0001_initial.sql` from [contracts/schema.sql](contracts/schema.sql), defining enums `greeting_presentation ('plain','card')`, `recurrence_kind ('once','daily','weekly')`, `schedule_state ('active','suspended')`, `delivery_kind ('greeting','scheduled','stream_alert','video_alert','voice_created','config_change')`, `delivery_outcome ('delivered','skipped','suppressed','failed')`, `feature_kind ('greetings','schedules','voice','twitch','youtube')`, `upstream_status ('pending','active','revoked','failed')`
- [ ] T031 Add the `guild` table to `crates/gaea-store/migrations/0001_initial.sql` with `timezone TEXT NOT NULL`, `removed_at`/`purge_after` nullable, `max_greetings_per_minute INTEGER NOT NULL DEFAULT 10`, `max_messages_per_minute INTEGER NOT NULL DEFAULT 30`, and `CONSTRAINT dormancy_coherent CHECK ((removed_at IS NULL) = (purge_after IS NULL))`
- [ ] T032 Add the `feature_kind` enum and the `guild_feature_state` table to `crates/gaea-store/migrations/0001_initial.sql` per [contracts/schema.sql](contracts/schema.sql), keyed `PRIMARY KEY (guild_id, feature)` with `enabled BOOLEAN NOT NULL DEFAULT false`, `changed_by BIGINT` and `changed_at TIMESTAMPTZ NOT NULL DEFAULT now()`. FR-006 requires all five features independently disableable; only greetings and voice have a settings table of their own, so without this three of the five have nowhere to record being disabled — the exact state `/gaea disable` exists to reach
- [ ] T033 Add the `delivery_record` table plus `CREATE UNIQUE INDEX delivered_once ON delivery_record (guild_id, kind, subject) WHERE outcome = 'delivered'` to `crates/gaea-store/migrations/0001_initial.sql` — this constraint is what makes exactly-once a database property rather than an application hope. Add the `delivery_retention` index too; the 90-day sweep enforcing it belongs to spec 002 (FR-049), this feature owns the table
- [ ] T034 Implement `bins/gaea-migrate/src/main.rs` applying migrations with the PRIVILEGED account, refusing to run if handed the DML-only credential; migrations MUST NOT run at service startup (ADR-0004)
- [ ] T035 Implement the connection pool and `#[sqlx::test]` harness wiring in `crates/gaea-store/src/pool.rs`, with a committed offline query cache so CI can build without a live database
- [ ] T036 Implement the single audit writer in `crates/gaea-store/src/audit.rs` recording actor, guild, target, action, outcome and timestamp for every configuration change and every automated delivery. Every write path — the bot, the operator CLI, and later the dashboard — goes through it, so FR-003 and SC-012's "100% attributable" hold by construction rather than by each call site remembering
- [ ] T037 Implement `LISTEN`/`NOTIFY` change propagation in `crates/gaea-store/src/notify.rs` so a configuration write reaches the bot within 30 seconds of commit (FR-018 of spec 002)

### Domain core

- [ ] T038 [P] Implement identifier newtypes `GuildId`, `ChannelId`, `MemberId`, `RoleId` in `crates/gaea-domain/src/ids.rs` so the compiler rejects passing a channel where a guild is expected
- [ ] T039 [P] Implement the `Clock` trait and a test clock in `crates/gaea-domain/src/clock.rs`, so time-dependent logic is testable without waiting
- [ ] T040 Write failing tests then implement platform limit constants and validators in `crates/gaea-domain/src/limits.rs`: 2,000 characters per message, 100 characters per channel name, 500 channels per guild

### Discord boundary ([contracts/discord-boundary.md](contracts/discord-boundary.md))

- [ ] T041 Define the `DiscordGateway` trait in `crates/gaea-discord/src/boundary.rs` exposing exactly the operations listed in [contracts/discord-boundary.md](contracts/discord-boundary.md) and no more; every signature uses `gaea-domain` types
- [ ] T042 Define the `GuildEvent` enum in `crates/gaea-discord/src/events.rs` with exactly `MemberJoined`, `VoiceStateChanged`, `ChannelDeleted`, `GuildRemoved`, `GuildAdded`, `InteractionReceived`, `Connected`, `Disconnected`; anything else Discord sends is discarded at the boundary
- [ ] T043 Implement the in-memory test double in `crates/gaea-discord/src/testing.rs` recording every call and scripting the failure modes Principle V requires: HTTP 429 with `retry_after`, gateway resume, invalid session, missing permission, deleted channel, guild at the 500-channel limit
- [ ] T044 Write contract tests in `tests/contract/discord_failure_modes.rs` covering each scripted failure mode above; no test may open a socket to Discord
- [ ] T045 Implement the Twilight-backed boundary in `crates/gaea-discord/src/twilight_impl.rs` requesting intents `GUILDS`, `GUILD_VOICE_STATES` and `GUILD_MEMBERS` only — `MESSAGE_CONTENT` and `GUILD_PRESENCES` MUST NOT be requested (Principle I, least privilege)
- [ ] T046 Write failing tests in `crates/gaea-discord/src/ratelimit.rs` asserting the limiter yields before exhausting a per-route bucket, respects the 50-requests-per-second global limit, and treats a received 429 as a defect rather than as normal flow control (Principle V, test-first for security controls)
- [ ] T047 Implement the proactive rate limiter in `crates/gaea-discord/src/ratelimit.rs` honouring per-route `X-RateLimit-Bucket`/`-Remaining`/`-Reset-After` headers and the 50-requests-per-second global limit; a received 429 is logged as a defect in the limiter and surfaced as a metric
- [ ] T048 Implement mention suppression in `crates/gaea-discord/src/send.rs` so every send path sets `allowed_mentions` rather than escaping text, and no method exists that sends without it (FR-004). A mass-notification send is a separately named method

### Guild lifecycle (FR-009 through FR-009c, FR-010)

- [ ] T049 Write failing tests in `crates/gaea-store/src/guild.rs` for dormancy (FR-009): removal sets `removed_at` and `purge_after = removed_at + 30 days`; re-add within the window clears both; purge after the window is irrecoverable
- [ ] T050 Implement guild repository methods in `crates/gaea-store/src/guild.rs` where EVERY method feeding a feature runner filters `removed_at IS NULL`, so FR-009a's "dormant data does nothing" cannot be violated by forgetting a check
- [ ] T051 Implement the purge sweep in `bins/gaea-bot/src/lifecycle/purge.rs` reconciling against the stored `purge_after` date rather than firing a timer, so a deletion missed while offline is performed on the next start (FR-009c)
- [ ] T052 Implement restoration announcement in `bins/gaea-bot/src/lifecycle/restore.rs` telling the operator that a prior configuration was restored and when it was last active (FR-009b)
- [ ] T053 Implement per-guild outbound rate ceilings in `crates/gaea-domain/src/rate.rs` evaluated against `delivery_record` within a window rather than held in memory, so a restart cannot reset a guild's consumption (FR-010)

### Bot process skeleton (ADR-0003)

- [ ] T054 Implement the gateway event loop in `bins/gaea-bot/src/main.rs` consuming `GuildEvent` from the boundary, with reconnect and resume handling
- [ ] T055 Write a failing test in `bins/gaea-bot/src/singleton.rs` asserting a second bot instance refuses to start while the first holds the advisory lock, and that the lock is released on clean shutdown. At a single shard two instances duplicate every event, so this guards FR-014, FR-026, FR-032 and FR-038 at once
- [ ] T056 Implement a startup advisory lock in `bins/gaea-bot/src/singleton.rs` so a second bot instance refuses to start — at a single shard, two instances would duplicate every event and break FR-014, FR-026, FR-032 and FR-038
- [ ] T057 Implement the feature-state repository in `crates/gaea-store/src/feature_state.rs`, and make every repository method feeding a feature runner assert BOTH `enabled = true` for that feature and `removed_at IS NULL` for the guild, so neither FR-006 nor FR-009a can be forgotten independently
- [ ] T058 Implement the emergency disable command `/gaea disable <feature>` in `bins/gaea-bot/src/commands/disable.rs`, authorized to owner, administrator or designated manager with a default-deny branch — absence of a positive authorization is a denial, never an allow (FR-002). It MUST only disable, never enable or change any other setting (FR-042 of spec 002), and MUST work without the dashboard being reachable. **Ship its help text, required permissions and rate-limit behaviour in `docs/commands.md` in this same change** — Principle II requires that, not a later documentation pass
- [ ] T059 Implement the operator CLI skeleton in `bins/gaea-admin/src/main.rs` sharing `gaea-domain`'s validation rather than reimplementing it, so a configuration it accepts is one the dashboard would also accept (ADR-0010)

**Checkpoint**: CI green, migrations apply, bot connects to a gateway and idles. No feature yet.

---

## Phase 3: User Story 1 — Greet new members automatically (Priority: P1)

**Goal**: A configured greeting is posted when a member joins, rendered inertly and previewable.

**Independent test**: Configure a greeting and channel in a test guild, join with a second account,
observe the rendered greeting. Delivers value with nothing else built.

- [ ] T060 [P] [US1] Write failing tests in `crates/gaea-domain/src/greeting/template.rs` for placeholder substitution covering member mention, member display name, guild name, and resulting member count (FR-012)
- [ ] T061 [P] [US1] Write failing DENY-PATH tests in `crates/gaea-domain/src/greeting/validate.rs`: an unknown placeholder is rejected; a template that cannot render within 2,000 characters under worst-case substitution is rejected; an operator-supplied image address is rejected anywhere in a greeting (FR-005, FR-012b, FR-012d)
- [ ] T062 [US1] Implement the greeting template parser and renderer in `crates/gaea-domain/src/greeting/template.rs`
- [ ] T063 [US1] Implement greeting validation in `crates/gaea-domain/src/greeting/validate.rs` per the deny-path tests above
- [ ] T064 [US1] Add the `welcome_setting` table to `crates/gaea-store/migrations/0002_welcome.sql` with `presentation greeting_presentation NOT NULL DEFAULT 'plain'`, `card_colour INTEGER` nullable, and NO `enabled` column — enabled state lives in `guild_feature_state`, and `CONSTRAINT colour_only_for_card CHECK (card_colour IS NULL OR presentation = 'card')`. The schema has NO column for an operator-supplied image address, which is how FR-012b is enforced structurally
- [ ] T065 [US1] Implement the welcome setting repository in `crates/gaea-store/src/welcome.rs` with `#[sqlx::test]` coverage
- [ ] T066 [US1] Write a failing test in `tests/integration/greeting_mentions.rs` asserting that a joining member whose display name contains `@everyone` produces a message notifying no one but the joining member (FR-004, SC-007) — this is a security test, not a cosmetic one
- [ ] T067 [US1] Implement the greeting runner in `bins/gaea-bot/src/features/greeting.rs` posting within 5 seconds of the join event (FR-011, SC-002)
- [ ] T068 [US1] Implement card presentation in `bins/gaea-bot/src/features/greeting_card.rs` carrying the operator's colour and the joining member's own avatar, and posting WITHOUT an avatar rather than failing or showing a broken image when the member has none (FR-012a, FR-012c)
- [ ] T069 [US1] Implement at-most-one-greeting-per-join in `crates/gaea-store/src/delivery.rs` using the `delivered_once` index on `delivery_record` with `kind = 'greeting'` (FR-014)
- [ ] T070 [US1] Implement per-guild greeting throttling in `bins/gaea-bot/src/features/greeting.rs` against `max_greetings_per_minute`, recording the throttling rather than dropping it silently (FR-015)
- [ ] T071 [US1] Implement failure reporting in `bins/gaea-bot/src/features/greeting.rs` for a deleted channel or lost permission: suppress the message, record the failure, and store an operator-actionable reason — never an error code (FR-007)
- [ ] T072 [US1] Implement preview rendering in `crates/gaea-domain/src/greeting/preview.rs` returning a rendered message with sample values, visible only to the requesting operator (FR-013)
- [ ] T073 [US1] Write a test in `tests/integration/greeting_no_fetch.rs` observing all outbound requests while exercising every greeting configuration, asserting the bot fetches nothing beyond Discord and the member avatar the platform supplies — no guild can cause it to fetch remote content (FR-012b, SC-002a)
- [ ] T074 [US1] Add `gaea-admin` subcommands for greeting configuration in `bins/gaea-admin/src/commands/greeting.rs` applying the same validation as T063 and writing `config_change` audit rows through the shared writer (FR-003)
- [ ] T075 [US1] Write an integration test in `tests/integration/greeting_flow.rs` covering all six acceptance scenarios in User Story 1 of [spec.md](spec.md)

**Checkpoint**: US1 independently demonstrable against a real guild.

---

## Phase 4: User Story 2 — Self-service temporary voice channels (Priority: P2)

**Goal**: Joining a hub channel creates a channel the member owns; it disappears when empty.

**Independent test**: Designate a hub, join it as a non-privileged member, confirm creation and
placement, leave, confirm removal.

- [ ] T076 [P] [US2] Write failing tests in `crates/gaea-domain/src/voice/rules.rs` for ownership, per-member concurrency and creation-rate rules
- [ ] T077 [P] [US2] Write failing DENY-PATH tests in `crates/gaea-domain/src/voice/rules.rs`: a member may not rename, limit or lock a channel they do not own, and the denial reveals nothing about the other channel (FR-018)
- [ ] T078 [US2] Add `temporary_voice_setting` (with NO `enabled` column — see `guild_feature_state`) and `temporary_voice_channel` tables in `crates/gaea-store/migrations/0003_voice.sql` with `empty_grace_seconds INTEGER NOT NULL DEFAULT 30`, `max_per_member INTEGER NOT NULL DEFAULT 1`, `creations_per_window INTEGER NOT NULL DEFAULT 3`, `window_seconds INTEGER NOT NULL DEFAULT 600`
- [ ] T079 [US2] Add `CREATE UNIQUE INDEX one_channel_per_owner ON temporary_voice_channel (guild_id, owner_id)` to `crates/gaea-store/migrations/0003_voice.sql` — this is what enforces FR-016c at the database rather than by application check
- [ ] T080 [US2] Implement the voice repository in `crates/gaea-store/src/voice.rs` with `#[sqlx::test]` coverage
- [ ] T081 [US2] Implement channel name sanitisation in `crates/gaea-domain/src/voice/name.rs` to the platform's 100-character limit and permitted character set (FR-022)
- [ ] T082 [US2] Implement hub-join detection and channel creation in `bins/gaea-bot/src/features/voice/create.rs`, creating in the configured category and moving the member within 3 seconds (FR-016, FR-016a, SC-003)
- [ ] T083 [US2] Implement FR-016b in `bins/gaea-bot/src/features/voice/create.rs`: a member is NEVER left waiting in the hub — on success they are moved out, and on refusal or failure they are removed from the hub and told the reason. Without this, every subsequent voice event re-triggers the attempt
- [ ] T084 [US2] Implement FR-016c in `bins/gaea-bot/src/features/voice/create.rs`: a member rejoining the hub while already owning a channel is returned to it rather than given a second
- [ ] T085 [US2] Implement FR-020a in `bins/gaea-bot/src/features/voice/create.rs`: a channel created but not moved into is removed, so a failed creation never adds a permanent empty channel
- [ ] T086 [US2] Implement the 500-channel refusal path in `bins/gaea-bot/src/features/voice/create.rs` with an explanatory message and no partial channel left behind (FR-020)
- [ ] T087 [US2] Implement per-member concurrency and creation-rate limits in `bins/gaea-bot/src/features/voice/limits.rs`, recording each refusal in the audit log (FR-019)
- [ ] T088 [US2] Implement empty-channel deletion in `bins/gaea-bot/src/features/voice/reap.rs` driven by `empty_since`, deleting within the grace period and within 30 seconds (FR-017, SC-003)
- [ ] T089 [US2] Implement restart reconciliation in `bins/gaea-bot/src/features/voice/reconcile.rs` comparing `temporary_voice_channel` against live channels and deleting orphans (FR-021)
- [ ] T090 [US2] Implement misconfiguration reporting in `bins/gaea-bot/src/features/voice/mod.rs` when the hub channel no longer exists or the bot cannot act on it, attempting no creation (FR-020b)
- [ ] T091 [US2] Implement ownership transfer on owner departure in `bins/gaea-bot/src/features/voice/ownership.rs` (FR-018, scenario 7)
- [ ] T092 [US2] Implement the `/voice rename|limit|lock|unlock|transfer` commands in `bins/gaea-bot/src/commands/voice.rs` per [contracts/discord-commands.md](contracts/discord-commands.md), acting only on the live channel the invoker owns and touching no stored configuration. **Ship their help text, required permissions and rate-limit behaviour in `docs/commands.md` in this same change** (Principle II)
- [ ] T093 [US2] Add `gaea-admin` subcommands for hub configuration in `bins/gaea-admin/src/commands/voice.rs`, writing `config_change` audit rows through the shared writer (FR-003)
- [ ] T094 [US2] Write an integration test in `tests/integration/voice_flow.rs` covering all ten acceptance scenarios in User Story 2 of [spec.md](spec.md)

**Checkpoint**: US2 independently demonstrable; SC-008's seven-day soak can begin.

---

## Phase 5: User Story 3 — Scheduled channel messages (Priority: P3)

**Goal**: One-time, daily and weekly messages delivered exactly once in the guild's timezone.

**Independent test**: Schedule a message minutes out, confirm delivery; schedule and cancel another,
confirm it does not post.

- [ ] T095 [P] [US3] Write failing tests in `crates/gaea-domain/src/schedule/dst.rs` for the two daylight-saving rules: a local time that does not exist on the spring-forward day fires ONCE at the first instant the clock reaches or passes it (FR-023b); a local time occurring twice on the fall-back day fires ONCE, on the first occurrence (FR-023c)
- [ ] T096 [US3] Implement occurrence computation in `crates/gaea-domain/src/schedule/occurrence.rs` resolving against the guild's IANA timezone at the moment needed, never precomputed at creation, so a jurisdiction changing its rules is handled by updating tz data
- [ ] T097 [US3] Write the SC-004a test in `crates/gaea-domain/src/schedule/dst.rs` replaying a full simulated year against a transition-observing timezone with the injected `Clock`, asserting exactly one firing per intended occurrence. This runs in milliseconds and is the reason the logic is pure
- [ ] T098 [US3] Add the `scheduled_message` table in `crates/gaea-store/migrations/0004_schedule.sql` storing `local_time TIME NOT NULL` plus the guild's zone — NEVER a pre-resolved instant — with `CONSTRAINT weekday_iff_weekly CHECK ((recurrence = 'weekly') = (weekday IS NOT NULL))`, `CONSTRAINT date_iff_once CHECK ((recurrence = 'once') = (fire_date IS NOT NULL))`, `CONSTRAINT weekday_range CHECK (weekday IS NULL OR weekday BETWEEN 0 AND 6)`, and `CONSTRAINT suspended_has_reason CHECK (state <> 'suspended' OR suspend_reason IS NOT NULL)`
- [ ] T099 [US3] Add `CREATE INDEX schedule_due ON scheduled_message (next_occurrence) WHERE state = 'active'` to `crates/gaea-store/migrations/0004_schedule.sql`
- [ ] T100 [US3] Implement the claim-based queue in `crates/gaea-store/src/schedule.rs` using `SELECT ... FOR UPDATE SKIP LOCKED`, setting `last_delivered_occurrence` in the SAME transaction that sends — this is what makes FR-026's exactly-once hold across restarts and concurrent instances
- [ ] T101 [US3] Write a failing test in `tests/integration/schedule_exactly_once.rs` running two concurrent claimers against one due schedule and asserting exactly one delivery (FR-026)
- [ ] T102 [US3] Implement the scheduler runner in `bins/gaea-bot/src/features/schedule/runner.rs` delivering within 60 seconds of the scheduled instant (FR-025, SC-004)
- [ ] T103 [US3] Implement the 15-minute catch-up rule in `bins/gaea-bot/src/features/schedule/runner.rs`: an occurrence more than 15 minutes late is skipped and the skip recorded; skipping an occurrence of a repeating schedule MUST NOT cancel or suspend it (FR-027)
- [ ] T104 [US3] Implement FR-027a in `bins/gaea-bot/src/features/schedule/runner.rs`: at most one message per occurrence, and NO backlog of missed occurrences delivered after an outage
- [ ] T105 [US3] Implement suspension on delivery failure in `bins/gaea-bot/src/features/schedule/runner.rs` for a missing channel or insufficient permission, with an operator-readable reason rather than indefinite retry (FR-028)
- [ ] T106 [US3] Implement timezone change handling in `crates/gaea-domain/src/schedule/occurrence.rs` preserving each schedule's stated local time and recomputing `next_occurrence` (FR-023d)
- [ ] T107 [US3] Implement listing with unambiguous timezone qualification in `bins/gaea-admin/src/commands/schedule.rs`, showing a repeating schedule's next occurrence as a concrete date and time rather than only a pattern (FR-029)
- [ ] T108 [US3] Add `gaea-admin` create, edit and cancel subcommands in `bins/gaea-admin/src/commands/schedule.rs`, requiring the guild timezone to be set before a schedule can be created, and writing `config_change` audit rows through the shared writer (FR-023, FR-023a, FR-024, FR-003)
- [ ] T109 [US3] Write an integration test in `tests/integration/schedule_flow.rs` covering all ten acceptance scenarios in User Story 3 of [spec.md](spec.md)

**Checkpoint**: US3 independently demonstrable, including both daylight-saving days without waiting for March.

---

## Phase 6: User Story 4 — Twitch live alerts (Priority: P4)

**Goal**: One alert per broadcast, delivered within 2 minutes, surviving revocation and outage.

**Independent test**: Subscribe a test guild to an offline streamer, have them go live, confirm
exactly one alert.

**Note**: This story introduces a minimal `gaea-web` binary hosting ONLY the platform callback
endpoints. The dashboard itself belongs to spec 002; [plan.md](plan.md) assigns `gaea-web` to that
spec, so this phase creates the binary and 002 extends it. The bot process must gain no inbound
network surface (ADR-0003).

- [ ] T110 [US4] Create `bins/gaea-web/Cargo.toml` and `src/main.rs` with Axum, serving ONLY the platform callback endpoints and a health endpoint for now
- [ ] T111 [US4] Write failing tests in `bins/gaea-web/src/proxy.rs` asserting a forwarding header from an untrusted source is ignored, one from a configured trusted proxy is honoured, and the application refuses to start when the trusted-proxy configuration is absent or contradictory. Getting this wrong makes per-client rate limiting inert and the audit origin forgeable (FR-037 of spec 002, Principle V)
- [ ] T112 [US4] Implement trusted-proxy client-address extraction in `bins/gaea-web/src/proxy.rs` from a configured trusted set, ignoring client-supplied forwarding headers from untrusted sources — without this, per-client rate limiting is inert and the audit origin is forgeable (FR-037 of spec 002)
- [ ] T113 [P] [US4] Write failing tests in `bins/gaea-web/src/callbacks/twitch_verify.rs` for HMAC-SHA256 verification over message id, timestamp and raw body in constant time, rejecting a forged signature and a timestamp outside the replay window BEFORE any parsing (FR-035d)
- [ ] T114 [US4] Implement Twitch signature verification in `bins/gaea-web/src/callbacks/twitch_verify.rs` reading `Twitch-Eventsub-Message-Signature`
- [ ] T115 [US4] Add `twitch_upstream` and `stream_subscription` tables in `crates/gaea-store/migrations/0005_twitch.sql` with `CONSTRAINT secret_length CHECK (length(hmac_secret) BETWEEN 10 AND 100)` — the platform's own requirement — and `CONSTRAINT revoked_has_reason CHECK (status <> 'revoked' OR revocation_reason IS NOT NULL)`
- [ ] T116 [US4] Implement per-subscription secret generation in `crates/gaea-domain/src/alerts/secret.rs` from a CSPRNG, ASCII, within the 10-to-100 character range (FR-035d, Principle I)
- [ ] T117 [US4] Implement one-upstream-per-broadcaster creation in `crates/gaea-store/src/twitch.rs`, fanned out to every guild following that broadcaster — Twitch charges cost per subscription, not per guild (FR-035b)
- [ ] T118 [US4] Implement FR-035g in `crates/gaea-store/src/twitch.rs`: a duplicate upstream subscription request is treated as success, so a restart cannot leave guilds silently unsubscribed
- [ ] T119 [US4] Write a failing test in `tests/integration/twitch_ack_deadline.rs` asserting the callback acknowledges BEFORE announcement work begins (FR-035c). A handler coupled to Discord's latency accumulates delivery failures and Twitch unsubscribes the application from every streamer at once
- [ ] T120 [US4] Implement persist-then-acknowledge in `bins/gaea-web/src/callbacks/twitch.rs`: write the notification to storage, respond 2XX, and hand announcement off as separate work (FR-035c)
- [ ] T121 [US4] Implement `webhook_callback_verification` challenge echo in `bins/gaea-web/src/callbacks/twitch.rs`
- [ ] T122 [US4] Implement revocation handling in `bins/gaea-web/src/callbacks/twitch.rs` for each documented reason — `notification_failures_exceeded` (a defect here, must alarm), `user_removed` (retire the guild subscriptions), `version_removed` (deployment-level fault), `authorization_revoked`, `moderator_removed` — recording the stated reason and surfacing it as an operator-visible fault. A discarded revocation is the most likely way this feature dies quietly (FR-035e, SC-005b)
- [ ] T123 [US4] Implement message-id deduplication in `bins/gaea-web/src/callbacks/twitch.rs` so a Twitch redelivery is acknowledged and discarded
- [ ] T124 [US4] Implement broadcast deduplication in `bins/gaea-bot/src/features/alerts/twitch.rs` against `last_announced_broadcast_id`, treating a reconnect inside the configured window as the same broadcast (FR-032)
- [ ] T125 [US4] Implement the alert announcement in `bins/gaea-bot/src/features/alerts/twitch.rs` carrying stream title, category and link, within 2 minutes of the broadcast starting (FR-031, FR-034, SC-005)
- [ ] T126 [US4] Implement streamer validation at subscription time in `crates/gaea-store/src/twitch.rs`, rejecting an unknown name and storing nothing (FR-033)
- [ ] T127 [US4] Implement Helix rate-limit handling in `bins/gaea-bot/src/features/alerts/twitch_api.rs` honouring `Ratelimit-Limit`, `Ratelimit-Remaining` and `Ratelimit-Reset`, and waiting for the reset instant on a 429 rather than retrying blindly (FR-035f)
- [ ] T128 [US4] Implement the per-guild ceiling of 10 Twitch subscriptions and the deployment ceiling of 100 distinct broadcasters in `crates/gaea-domain/src/alerts/ceilings.rs`, with a refusal naming the deployment as the cause rather than appearing to be a fault in the guild's configuration (FR-035a, FR-042b)
- [ ] T129 [US4] Implement the reconciliation sweep in `bins/gaea-bot/src/features/alerts/reconcile.rs` comparing observed state against the last-announced identifier and dropping anything past the staleness threshold, so no backlog burst follows an outage (FR-043). At 100 broadcasters this is a single `Get Streams` call costing 1 of 800 points per minute
- [ ] T130 [US4] Add `gaea-admin` subscribe, list and remove subcommands in `bins/gaea-admin/src/commands/twitch.rs`, writing `config_change` audit rows through the shared writer (FR-030, FR-035, FR-003)
- [ ] T131 [US4] Write an integration test in `tests/integration/twitch_flow.rs` covering all nine acceptance scenarios in User Story 4 of [spec.md](spec.md), including an induced revocation and a one-hour outage

**Checkpoint**: US4 independently demonstrable, including revocation and outage recovery.

---

## Phase 7: User Story 5 — YouTube upload alerts (Priority: P5)

**Goal**: One alert per video, within 10 minutes, with leases that never lapse unnoticed.

**Independent test**: Subscribe a test guild to a YouTube channel, publish a video, confirm exactly
one alert.

- [ ] T132 [P] [US5] Write failing tests in `bins/gaea-web/src/callbacks/youtube_verify.rs` for WebSub signature verification against the shared secret supplied at subscription time, rejecting forged content before parsing
- [ ] T133 [US5] Add `youtube_upstream`, `video_subscription` and `announced_video` tables in `crates/gaea-store/migrations/0006_youtube.sql`, with `announced_video` keyed `PRIMARY KEY (subscription_id, video_id)` so FR-038's at-most-one-alert-per-video is a uniqueness constraint rather than a search
- [ ] T134 [US5] Implement the WebSub subscribe and confirmation-challenge flow in `bins/gaea-web/src/callbacks/youtube.rs` against `pubsubhubbub.appspot.com` for the topic `youtube.com/feeds/videos.xml?channel_id=…`
- [ ] T135 [US5] Implement lease tracking in `crates/gaea-store/src/youtube.rs` storing `lease_expires_at` derived from the `lease_seconds` the hub RETURNS — never a hardcoded interval, because assuming a duration is how a renewal schedule silently drifts past expiry (FR-042c)
- [ ] T136 [US5] Implement lease renewal scheduling in `bins/gaea-bot/src/features/alerts/youtube_renew.rs`, recording a failed renewal as an operator-visible fault. A lapsed lease produces no error of its own — that channel's uploads are simply never announced again (FR-042c, SC-005b)
- [ ] T137 [US5] Implement one-upstream-per-channel creation in `crates/gaea-store/src/youtube.rs`, fanned out to subscribing guilds (FR-042d)
- [ ] T138 [US5] Implement persist-then-acknowledge for YouTube notifications in `bins/gaea-web/src/callbacks/youtube.rs`, matching the Twitch discipline
- [ ] T139 [US5] Implement the subscription-start cutoff in `bins/gaea-bot/src/features/alerts/youtube.rs` so nothing published before `subscribed_at` is announced, evaluated against each entry's publication time rather than its feed position — the feed delivers a back catalogue on first push (FR-039)
- [ ] T140 [US5] Implement video deduplication in `bins/gaea-bot/src/features/alerts/youtube.rs` against `announced_video`, so an edited title produces no second alert (FR-038)
- [ ] T141 [US5] Implement content-type filtering in `crates/gaea-domain/src/alerts/filter.rs` excluding livestreams and short-form videos when the guild's filter says so (FR-040)
- [ ] T142 [US5] Implement channel validation at subscription time in `crates/gaea-store/src/youtube.rs`, rejecting an unknown channel and storing nothing (FR-041)
- [ ] T143 [US5] Implement the per-guild ceiling of 10 YouTube subscriptions and the deployment ceiling of 100 distinct channels in `crates/gaea-domain/src/alerts/ceilings.rs` (FR-042a, FR-042b)
- [ ] T144 [US5] Extend the reconciliation sweep in `bins/gaea-bot/src/features/alerts/reconcile.rs` to cover YouTube, catching gaps from lapsed leases and dropping stale events (FR-043)
- [ ] T145 [US5] Add `gaea-admin` subscribe, list and remove subcommands in `bins/gaea-admin/src/commands/youtube.rs`, writing `config_change` audit rows through the shared writer (FR-036, FR-042, FR-003)
- [ ] T146 [US5] Write an integration test in `tests/integration/youtube_flow.rs` covering all seven acceptance scenarios in User Story 5 of [spec.md](spec.md), including a deliberately expired lease and a one-hour YouTube outage with recovery, confirming no crash, no false alerts and no backlog burst (SC-011)

**Checkpoint**: All five stories complete and independently demonstrable.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [ ] T147 [P] Write the operator documentation in `docs/operating.md` covering required intents, the permissions to invite with, secret file layout, the two database roles, and the trusted-proxy configuration
- [ ] T148 [P] Add a log-redaction assertion test in `tests/integration/log_redaction.rs` verifying no secret, token or message content appears in captured output from a full run of every feature (Principle VI)
- [ ] T149 [P] Add a metrics-label assertion test in `tests/integration/metrics_labels.rs` verifying the endpoint carries no guild-identifying labels, and document its non-public binding in `docs/operating.md` (Principle VI, ADR-0009)
- [ ] T150 Run the SC-010 fault-injection test in `tests/integration/isolation.rs` confirming one guild's misconfiguration or external-service failure never degrades another guild, and that no query serving one guild can reference another (FR-001, FR-008, SC-010)
- [ ] T151 Run the SC-013 and SC-014 dormancy tests in `tests/integration/dormancy.rs`: no automated action for a guild the bot is not in, and irrecoverable deletion 30 days after removal including when the bot was offline on the due day
- [ ] T152 Measure and record the actual YouTube WebSub lease duration granted by the hub, and confirm the renewal schedule derives from it — the one open item in [docs/adr/README.md](../../docs/adr/README.md)
- [ ] T153 Run `cargo doc --workspace --no-deps` and record the audit result in `docs/compliance-audit.md`, confirming every public item is documented and every `#[allow]` across `crates/` and `bins/` carries an inline justification naming the reason (Principle II)
- [ ] T154 Write a cross-cutting duplicate-suppression test in `tests/integration/exactly_once_across_restart.rs` spanning at least one full restart and one simulated redeployment, asserting zero duplicates for all four delivery kinds — greeting, scheduled, stream_alert, video_alert (SC-006)
- [ ] T155 Verify the V1 scale targets in `tests/integration/scale_smoke.rs` — 25 guilds, 2,500 members, 100 distinct upstream identities of each kind — confirming the stated alert and greeting latencies hold and that neither external service's request budget is exceeded (SC-005a, SC-009). A smoke check at the target size, not a load-modelling exercise
- [ ] T156 Execute [quickstart.md](quickstart.md) end to end against a real test guild and record the results, timing each feature's configuration to confirm it completes in under 3 minutes without consulting external documentation (SC-001)
- [ ] T157 Begin the SC-008 seven-day soak using the harness in `tests/integration/voice_soak.rs`, confirming no temporary voice channel persists more than 5 minutes after its last occupant leaves, including across a restart

---

## Dependencies

```text
Phase 1 (Setup)
  └─> Phase 2 (Foundational)  ⚠️ blocks everything
        ├─> Phase 3  US1 Greetings      (P1)  independent
        ├─> Phase 4  US2 Voice          (P2)  independent
        ├─> Phase 5  US3 Schedules      (P3)  independent
        ├─> Phase 6  US4 Twitch         (P4)  creates bins/gaea-web
        │     └─> Phase 7  US5 YouTube  (P5)  reuses gaea-web + reconcile sweep
        └─> Phase 8  Polish             requires all stories
```

US1, US2 and US3 are fully independent of one another and of the alert stories. US5 depends on US4
only for the `gaea-web` binary (T110–T112) and the reconciliation sweep (T129); given those, the
two alert stories are otherwise independent.

## Parallel Execution Examples

**Phase 1** — T003 through T008 are separate crate skeletons; T010, T011, T012 are separate config
files. All parallel.

**Phase 2** — the four observability tasks T026–T029 are separate modules. CI jobs T015–T020 are
separate workflow steps. Domain core T038, T039 are separate modules.

**Phase 3** — T060 and T061 write tests in different modules.

**Across stories** — once Phase 2 completes, three developers could take US1, US2 and US3
simultaneously; they share only `gaea-domain` primitives already built.

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + Phase 3 (US1).** Greetings exercise the full stack — configuration
store, permission model, template renderer, safe-output path, audit record — so proving them proves
the substrate every other story sits on. That is why US1 is P1 despite being the simplest feature.

**Incremental delivery.** Each story phase ends at a checkpoint where the bot is demonstrably useful
and can ship. If the schedule compresses, US4 and US5 are the tail to cut: they are the only stories
depending on third-party services, credentials and quotas.

**Test ordering within a story.** Deny-path tests before implementation, always. The deny path is
what matters in an authorization system and it is the path manual review reliably overlooks, because
the happy path is what gets exercised by hand.

**A note on the two alert stories.** Their scale ceilings are deliberately small for V1 and can be
raised later. Their *behaviours* cannot be deferred on the same grounds: a revoked Twitch
subscription (T122) and a lapsed WebSub lease (T136) fail identically at 25 guilds and at 1,000, and
neither announces itself. Those two tasks are where this feature quietly dies if they are skipped.
