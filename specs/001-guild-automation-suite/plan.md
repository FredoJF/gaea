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

**Testing**: `cargo test` for unit and integration; `cargo nextest` for parallel execution; SQLx
test fixtures against an ephemeral PostgreSQL instance for anything touching the schema; the
Discord boundary (ADR-0002 condition d) mocked at the trait so domain logic is testable without a
live gateway.

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
100 characters per channel name · Twitch and YouTube quotas bounding evaluation frequency
(ADR-0007).

**Scale/Scope**: 1,000 guilds, 10,000 concurrent members (SC-009). At Discord's documented one
shard per 2,500 guilds this is a **single gateway shard**, so the bot process is a singleton and
running two instances would duplicate every event. Up to 25 Twitch and 25 YouTube subscriptions per
guild (FR-035a, FR-042a), bounded deployment-wide by FR-042b.

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
| **tracing** | **0.1.44** | **2025-12-18** | **2026-05-30** | **FAIL — 108 days** |

Status: **FAIL on one dependency.** See Complexity Tracking.

Note in passing: Axum's repository was committed to yesterday, which materially softens the cadence
concern recorded in ADR-0005. Its slow release train is not dormancy.

### Principle IV — Current, Pinned, and Verified Dependencies

Exact pins with a committed `Cargo.lock`; CI asserts no pin more than 30 days behind latest stable
and fails immediately on any advisory; 72-hour publication cooldown before adopting a new release
except for advisory fixes; SBOM generated per release.

**Installed toolchain is rustc 1.93.0 (2026-01-19) against stable 1.98.1 (2026-09-01) — roughly 8
months stale, against a 30-day ceiling.** Twilight's MSRV is 1.89, so nothing blocks the update.

Status: **FAIL until the toolchain is updated and pinned via `rust-toolchain.toml`.** This is a
prerequisite task, not a design problem.

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
| Principle III — Engineering Merit | **FAIL** — `tracing` outside the 90-day activity window |
| Principle IV — Dependency Currency | **FAIL** — toolchain 8 months stale |
| Principle V — Proven Correctness | PASS |
| Principle VI — Observability | PASS |

Both failures are tracked below with proposed resolutions. Neither is a design flaw; both must be
closed before implementation begins.

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
└── gaea-web/                # spec 002

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

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| `tracing` 0.1.44 fails amended Principle III condition (b) — last commit 2026-05-30, 108 days against a 90-day window | Structured logging with span-propagated correlation identifiers is required by Principle VI. `tracing` is the ecosystem standard (851M downloads) and is already a transitive dependency of Tokio-based libraries, so rejecting it removes nothing from the dependency graph | Writing logging in-house rejected: it would mean reimplementing span propagation, the exact mechanism Principle VI depends on. Switching to `log` rejected: no span model, so correlation would have to be threaded by hand through every signature. **Resolution required before implementation** — either widen condition (b) to 180 days (a constitution PATCH/MINOR), or record a time-boxed exception with a scheduled re-check. This is the first live test of whether the ADR-0002 conditions are enforced or merely written down, and it should be answered deliberately |
| Toolchain 1.93.0 against stable 1.98.1 — 8 months, against Principle IV's 30-day ceiling | Not a design decision; an environment state predating the constitution | No alternative. Update to 1.98.1 and pin via `rust-toolchain.toml` as the first implementation task. MSRV 1.89 for Twilight means nothing blocks it |
| Three binaries and six library crates for one feature set | ADR-0003's two-process topology is what makes SC-014 structural; ADR-0004's separate migration account is required by the constitution; the crate split is what makes deny-path testing and Twilight replaceability possible | A single binary was rejected in ADR-0003 because a fault in the public-facing half would take the gateway down, failing SC-014 by construction. A single crate was rejected because domain logic would then depend on Twilight and SQLx, making Principle V's deny-path tests require a live gateway and database |
