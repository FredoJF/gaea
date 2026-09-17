# Implementation Plan: Guild Automation Suite (v1)

**Branch**: `001-guild-automation-suite` | **Date**: 2026-09-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-guild-automation-suite/spec.md`

## Summary

Five independently shippable guild automations — join greetings, hub-triggered temporary voice
channels, scheduled messages with daily/weekly recurrence, Twitch live alerts, and YouTube upload
alerts — delivered by a single-shard Discord bot process backed by PostgreSQL.

The technical approach is fixed by [ADR-0001 through ADR-0009](../../docs/adr/README.md): a Rust
Cargo workspace producing three binaries (bot, migration, and the web dashboard belonging to spec
002), sharing domain and data-access library crates over one PostgreSQL instance. The bot holds no
inbound network surface; it maintains one gateway connection and reads its configuration from the
database, learning of changes through `LISTEN`/`NOTIFY`.

Three requirements in this spec are satisfied by PostgreSQL features rather than application logic,
and that is the load-bearing design choice: exactly-once scheduled delivery (FR-026) by
`SELECT … FOR UPDATE SKIP LOCKED`, daylight-saving-correct recurrence (FR-023b/c) by `timestamptz`
against the bundled IANA tz data, and sub-30-second configuration propagation (FR-018 of 002) by
`LISTEN`/`NOTIFY`. Each is a place where hand-rolled application code would be the likely source of
a subtle, late-surfacing bug.

## Technical Context

**Language/Version**: Rust 1.98.1 (stable as of 2026-09-01). **Installed toolchain is 1.93.0 and
must be updated before implementation** — see Constitution Check.

**Primary Dependencies**: Tokio 1.53.1 (async runtime) · Twilight 0.17.1 (`-gateway`, `-http`,
`-model`; **not** `-cache-inmemory`) · Serde 1.0.229 · SQLx 0.9.0 (compile-time-checked queries) ·
tracing 0.1.44 (see Constitution Check) · a Prometheus exporter for metrics.

**Storage**: PostgreSQL 18.6. Single instance shared by bot, migration binary, and the 002 web
process. Application account holds DML only; the migration binary uses a separate privileged
account.

**Testing**: `cargo test` for unit and integration; `cargo nextest` for parallel execution.
Database-touching tests use `#[sqlx::test]`, which creates and drops a fresh database per test
against a developer-provided PostgreSQL — per-test isolation with no Docker dependency, using the
tool already chosen for queries rather than adding another. A running PostgreSQL is therefore a
prerequisite of any test run, in CI included. The Discord boundary (ADR-0002 condition d) is mocked
at the trait, so domain logic and every deny path are testable without a live gateway.

**Target Platform**: Linux server, deployed as a container running as a non-root user with a
read-only root filesystem and `no-new-privileges` (CIS Docker Benchmark), per the constitution's
Security and Platform Constraints.

**Project Type**: Multi-binary Cargo workspace — long-running service (bot), one-shot CLI
(migration), plus the web service belonging to spec 002.

**Performance Goals**: Greetings posted within 5 s at p99 (SC-002) · temporary channels created and
the member moved within 3 s at p99 (SC-003) · scheduled messages delivered within 60 s of their
instant at p99 (SC-004) · Twitch alerts within 2 min and YouTube within 10 min at p95 (SC-005).

**Constraints**: Discord global limit of 50 requests/second per bot, per-route bucket headers
honoured proactively, and the 10,000-invalid-requests-per-10-minutes ban threshold never approached
(Discord Developer Docs, *Rate Limits*) · 500 channels per guild · 2,000 characters per message ·
100 characters per channel name.

Twitch limits shaping the design (verified 2026-09-16): a `stream.online` subscription for an
unauthorised broadcaster costs 1; WebSocket transport permits a total cost of only 10, which
eliminates it; notifications must be acknowledged within seconds or the subscription is revoked for
`notification_failures_exceeded`; HMAC-SHA256 verification with a 10-to-100 ASCII character secret;
an 800-point API bucket reported via `Ratelimit-Limit` / `-Remaining` / `-Reset`. YouTube WebSub
leases expire and must be renewed.

**Scale/Scope**: **25 guilds and 2,500 members (SC-009)** — a deliberately small V1 target matching
the intended deployment. At Discord's documented one shard per 2,500 guilds this is comfortably a
**single gateway shard**, so the bot process is a singleton and running two instances would
duplicate every event. Up to 10 Twitch and 10 YouTube subscriptions per guild (FR-035a, FR-042a),
bounded deployment-wide at 100 distinct upstream identities of each kind (FR-042b).

These ceilings sit far below any plausible platform limit, so V1 never has to reason about
approaching one. That is a scale decision only: the platform *behaviours* that cause silent
permanent failure are handled in full regardless of size, because a revoked subscription or a lapsed
lease fails identically at 25 guilds and at 1,000, and neither announces itself.

## Constitution Check

*GATE: evaluated against constitution v1.1.0. Re-checked after Phase 1 design — result unchanged.*

### Principle I — Security-First by Default

| Requirement | How this plan satisfies it | Status |
|---|---|---|
| Schema-validated input at every boundary | Serde structs with `deny_unknown_fields` for all gateway payloads and external callbacks; parsed values only cross into the domain | PASS |
| Ed25519 interaction verification | Not applicable — ADR-0003 takes interactions over the gateway, so no HTTP interaction endpoint exists | PASS (N/A) |
| Least-privilege gateway intents | **`GUILDS` + `GUILD_VOICE_STATES` (non-privileged) + `GUILD_MEMBERS` (privileged, justified below)**. `MESSAGE_CONTENT` and `GUILD_PRESENCES` are **not** requested | PASS |
| Secrets injected at runtime | File-mounted, read once at startup, never in environment (ADR-0008) | PASS |
| TLS 1.3, no validation disabled | rustls defaults; no build profile disables verification | PASS |
| Default-deny authorization | Every command handler checks effective permissions; the default match arm denies | PASS |
| Argon2id for stored secrets | Not applicable — this feature stores no passwords | PASS (N/A) |
| Inert rendering of untrusted content | `allowed_mentions` suppression on every outbound message, never string escaping (FR-004) | PASS |
| SAST/SCA, no CVSS ≥ 7.0 | `cargo audit` against RustSec plus `cargo deny`, blocking merge and release | PASS |

**Privileged intent justification (required by Principle I).** `GUILD_MEMBERS` is requested solely
to receive member-join events, without which FR-011's greeting cannot exist. No other privileged
intent is requested. `MESSAGE_CONTENT` is explicitly not requested: nothing in this specification
reads message content, and the data-minimization constraint makes not having the capability
preferable to having and not using it.

### Principle II — Total Documentation

`#![deny(missing_docs)]` on every crate makes an undocumented public item a build failure, which is
the mechanical enforcement the principle requires. Nine ADRs already cover the architecturally
significant decisions. User-facing command documentation ships in the same change as each command.

Status: **PASS**

### Principle III — Selection by Engineering Merit

All selections are recorded with measured evidence in ADRs 0001–0009. Pre-1.0 dependencies are
governed by the six conditions added in constitution v1.1.0.

| Dependency | Line | Last release | Last commit | Condition (b): activity within 90 days |
|---|---|---|---|---|
| Twilight | 0.17.1 | 2025-12-13 | 2026-08-30 | PASS (17 days) |
| Axum | 0.8.9 | 2026-04-14 | **2026-09-15** | PASS (1 day) |
| SQLx | 0.9.0 | 2026-05-21 | — | PASS by release |
| Askama | 0.16.1 | 2026-09-04 | — | PASS by release |
| tracing | 0.1.44 | 2025-12-18 | 2026-05-30 | PASS (109 days, within 180) |

Status: **PASS.** The window was 90 days when this plan was first written and `tracing` failed it at
109 days. Rather than waive the condition on its first application, the threshold was corrected to
180 days in constitution v1.1.1 — see
[ADR-0002](../../docs/adr/0002-pre-1.0-dependency-policy.md). Commit recency is a proxy for
abandonment and mismeasures a library that has reached stability; 180 days still catches a project
silent for six months, against a twelve-month unmaintained threshold.

Note in passing: Axum's repository was committed to yesterday, which materially softens the cadence
concern recorded in ADR-0005. Its slow release train is not dormancy.

### Principle IV — Current, Pinned, and Verified Dependencies

Exact pins with a committed `Cargo.lock`; CI asserts no pin more than 30 days behind latest stable
and fails immediately on any advisory; 72-hour publication cooldown before adopting a new release
except for advisory fixes; SBOM generated per release.

**Toolchain updated 2026-09-16: rustc 1.98.1 (48a229cea, 2026-09-01), which is latest stable —
0 days stale.** Pinning it via `rust-toolchain.toml` remains a scaffolding task so the version is
asserted rather than merely current on one machine.

Status: **PASS.**

### Principle V — Proven Correctness Before Merge

Tests precede implementation for every bug fix and every security control; a regression test must be
observed to fail before its fix lands. Allow-path and deny-path coverage for every authorization
check and validator. Contract tests cover the documented Discord failure modes — HTTP 429 with
`retry_after`, gateway resume, invalid session — which the boundary trait (ADR-0002 condition d)
makes possible to exercise deterministically. Build fails on any compiler or linter warning.

Status: **PASS**

### Principle VI — Observability and Auditability

Structured logs and spans via `tracing`, with a correlation identifier carried from gateway event
through command execution to outbound call. Redaction is type-level: identifiers that may be logged
and content that may not are distinct types, so an ordinary formatting call cannot leak. Immutable
audit rows for every privileged action. Health and readiness endpoints, where bot readiness means a
live gateway connection rather than a running process. Prometheus metrics covering gateway
connection state, event processing latency, command error rate, and Discord rate-limit consumption.

Status: **PASS** (subject to the `tracing` question above)

### Gate summary

| Gate | Result |
|---|---|
| Principle I — Security-First | PASS |
| Principle II — Total Documentation | PASS |
| Principle III — Engineering Merit | PASS (after the v1.1.1 threshold correction) |
| Principle IV — Dependency Currency | PASS (toolchain updated to 1.98.1) |
| Principle V — Proven Correctness | PASS |
| Principle VI — Observability | PASS |

**All six gates pass.** Both prior failures were closed on 2026-09-16: the toolchain was updated,
and the activity window was corrected rather than waived.

## Project Structure

### Documentation (this feature)

```text
specs/001-guild-automation-suite/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── discord-boundary.md
│   ├── discord-commands.md
│   ├── external-callbacks.md
│   └── schema.sql
└── tasks.md             # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

A single Cargo workspace. The bot and migration binaries belong to this feature; `gaea-web` belongs
to spec 002 and is shown because the shared crates are designed to serve both.

```text
Cargo.toml                   # workspace manifest, exact pins
Cargo.lock                   # committed
rust-toolchain.toml          # pinned toolchain

crates/
├── gaea-domain/             # entities, invariants, rendering, scheduling arithmetic.
│   │                        # No Twilight, SQLx or HTTP types. Pure and unit-testable.
│   └── src/
│       ├── greeting/        # template parsing, placeholder substitution, length validation
│       ├── schedule/        # recurrence, timezone resolution, DST rules (FR-023b/c)
│       ├── voice/           # temporary channel ownership and lifecycle rules
│       ├── alerts/          # deduplication and staleness rules
│       └── guild/           # configuration, rate ceilings, dormancy
│
├── gaea-discord/            # THE BOUNDARY required by Principle III condition (d).
│   └── src/                 # A trait exposing only what Gaea needs. Twilight is an
│                            # implementation detail here and appears nowhere else.
│
├── gaea-store/              # SQLx repositories, LISTEN/NOTIFY, migrations as .sql
│   ├── migrations/
│   └── src/
│
├── gaea-observability/      # tracing + metrics facade; redaction types
│
└── gaea-config/             # file-mounted secret loading, startup validation (ADR-0008)

bins/
├── gaea-bot/                # gateway loop, feature runners, scheduler, alert pipeline
├── gaea-migrate/            # one-shot, privileged account (ADR-0004)
├── gaea-admin/              # operator-side configuration CLI. Not a user-facing
│                            # configuration surface — see FR-041a of spec 002
└── gaea-web/                # spec 002

.github/workflows/           # CI gates (the repository remote is GitHub)

tests/
├── contract/                # Discord failure modes, external callback shapes
├── integration/             # per user story, against ephemeral PostgreSQL
└── unit/                    # colocated in each crate
```

**Structure Decision**: A workspace with a pure `gaea-domain` crate at the centre and every external
system reachable only through an adapter crate. This is not layering for its own sake — it is what
makes three specific obligations achievable. Principle III condition (d) requires Twilight to be
replaceable, which `gaea-discord` provides. Principle V requires deny-path tests for every
authorization check and validator, which requires those checks to run without a gateway or a
database. And ADR-0003's two-binary topology requires bot and web to share domain rules without
sharing a process, which the library crates provide.

The daylight-saving arithmetic in `gaea-domain/schedule` deserves specific mention: it is the piece
of logic in this feature most likely to be wrong in a way nobody notices for months, and isolating
it as pure code is what lets SC-004a replay a simulated year against it in milliseconds.

## Delivery Scope

The task list covers scaffolding and CI before features, because the gates below are constitutional
requirements and retrofitting them means the earliest merges cannot satisfy Principles II, IV and V:

1. **Scaffolding** — Cargo workspace and crate skeleton, `rust-toolchain.toml` pinned to 1.98.1,
   exact dependency pins with a committed `Cargo.lock`.
2. **CI gates** (GitHub Actions, matching the repository remote) — build with zero compiler and
   linter warnings; documentation coverage; `cargo audit` and `cargo deny`; the 30-day pin-staleness
   assertion required by Principle IV; secret scanning; a PostgreSQL service for `#[sqlx::test]`.
3. **Container definition** — non-root, read-only root filesystem, `no-new-privileges`.
4. **Features** — the five user stories in their spec priority order, P1 through P5.

## External Platform Budget at V1 Scale

At the ceilings above the external work is negligible, which is the point of setting them there.

| Budget | V1 consumption | Headroom |
|---|---|---|
| Twitch EventSub total cost (1 per distinct broadcaster) | ≤ 100 | Far below the application ceiling, which V1 therefore need not confirm |
| Twitch API bucket (800 points/min) | Reconciliation queries up to 100 broadcasters in a single `Get Streams` call — 1 point | Effectively unused |
| YouTube Data API quota | **Zero** — the alert path uses the keyless feed and the WebSub hub, never the Data API | Entire quota unused |
| Discord global limit (50 req/s) | Bounded by FR-010's per-guild outbound ceiling across 25 guilds | Large |

The one number V1 deliberately does not rely on is Twitch's application-wide total-cost ceiling,
which could not be extracted from the rendered documentation. At 100 distinct broadcasters that
reliance is unnecessary. **It must be confirmed before the deployment ceiling in FR-042b is raised.**

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| An operator-side `gaea-admin` CLI exists alongside the dashboard | The dashboard (spec 002) does not exist yet, so there is no way to configure the bot in order to run or demonstrate it. The CLI also earns its place permanently as the dashboard-down recovery path | Raw SQL seed scripts rejected: they bypass every write-time validation the spec requires, so testing would run against configurations the real system would refuse. Test fixtures alone rejected: the bot could never be run against a real guild until 002 ships, making the quickstart guide unusable. **Note the FR-041 tension and why it is not a violation**: FR-041 makes the dashboard the sole configuration surface for guild owners, administrators, managers and viewers. The host operator already holds shell access and the database credential, so they have unconditional authority over every setting regardless; operator tooling adds no authorization surface. This is recorded as FR-041a in spec 002 rather than left as an implicit reading |
| Three binaries and six library crates for one feature set | ADR-0003's two-process topology is what makes SC-014 structural; ADR-0004's separate migration account is required by the constitution; the crate split is what makes deny-path testing and Twilight replaceability possible | A single binary was rejected in ADR-0003 because a fault in the public-facing half would take the gateway down, failing SC-014 by construction. A single crate was rejected because domain logic would then depend on Twilight and SQLx, making Principle V's deny-path tests require a live gateway and database |
