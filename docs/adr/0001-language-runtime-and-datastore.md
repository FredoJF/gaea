# ADR-0001: Language, Discord Library, Serialization, and Datastore

**Status**: Accepted. The constitutional deviation recorded below was resolved on 2026-09-16 by
[ADR-0002](0002-pre-1.0-dependency-policy.md), which amended Principle III (constitution v1.1.0).

**Date**: 2026-09-16

**Deciders**: Project maintainer

**Governs**: [001-guild-automation-suite](../../specs/001-guild-automation-suite/spec.md),
[002-web-management-dashboard](../../specs/002-web-management-dashboard/spec.md)

**Constitution**: Principle III (Selection by Engineering Merit, Not Popularity) requires this
record before implementation begins. Principle IV (Current, Pinned, and Verified Dependencies)
governs the versions pinned here.

---

## Context

Gaea is a security-first, self-hosted Discord bot. Its first version targets a small deployment of
roughly 25 guilds (SC-009, 001) with a publicly reachable web management dashboard (002). The workload has two
distinct shapes:

1. **High-fanout event processing** — a persistent gateway connection delivering member joins, voice
   state changes, and guild updates, requiring sustained low-latency handling (SC-002: 99% of
   greetings within 5 seconds; SC-003: voice channels created within 3 seconds).
2. **Burst-sensitive scheduled and polled work** — exactly-once scheduled delivery across restarts
   and concurrent instances (FR-026, 001), and duplicate-free alerting from two external platforms
   under their quota ceilings (SC-005a, 001).

Both must hold while the process is exposed to hostile public traffic (FR-040, 002) and while
handling untrusted, attacker-controlled input at every boundary (Principle I).

All measurements below were taken on **2026-09-16** from crates.io, static.rust-lang.org,
api.github.com, and endoflife.date. Every version is a point-in-time observation; Principle IV
requires CI to re-assert currency continuously rather than trusting this snapshot.

---

## Decision

| Layer | Selection | Version verified 2026-09-16 | License |
|---|---|---|---|
| Language / toolchain | Rust | 1.98.1 (48a229cea, 2026-09-01) | MIT OR Apache-2.0 |
| Async runtime | Tokio | 1.53.1 (2026-07-20) | MIT |
| Discord client | Twilight (modular crates) | 0.17.1 (2025-12-13) | ISC |
| Serialization | Serde | 1.0.229 (2026-07-18) | MIT OR Apache-2.0 |
| Datastore | PostgreSQL | 18.6 (EOL 2030-11-14) | PostgreSQL License |

Tokio is not an independent selection — it is entailed by Twilight, which is built on it. It is
recorded here for completeness and because its scheduler properties are part of the justification.

---

## Options Considered

### Language and runtime

| Criterion | Rust | Go | TypeScript / Node.js | Python |
|---|---|---|---|---|
| Memory safety without GC | Yes, compile-time | GC | GC | GC |
| Data-race freedom at compile time | Yes | No | N/A (single-threaded core) | No |
| Tail latency under load | No GC pauses | GC pauses, low but present | GC pauses | GIL contention |
| Exhaustive error handling enforced | Yes (`Result`, `#[must_use]`) | Convention only | No | No |
| Doc coverage enforceable at build | Yes (`#![deny(missing_docs)]`) | Partial | Lint only | Lint only |

**Evidence for memory safety as the deciding criterion.** Microsoft Security Response Center
reported that approximately 70% of CVEs it assigns annually are memory-safety issues (Matt Miller,
BlueHat IL 2019). The Chromium project reports the same proportion — roughly 70% of serious security
bugs are memory-safety bugs (Chromium Security, "Memory safety"). Google's Android team reported
memory-safety vulnerabilities falling from 76% of total in 2019 to 24% in 2024 as new development
moved to memory-safe languages (Google Security Blog, September 2024). CISA, NSA, FBI and
international partners name Rust among memory-safe languages in *The Case for Memory Safe Roadmaps*
(December 2023).

For a bot whose compromise is multi-tenant by construction — one token grants write access to every
guild that installed it (Principle I rationale) — eliminating an entire vulnerability class at
compile time is the single highest-leverage decision available. This is selection on defect class,
not on benchmark throughput.

**Why not Go**: Go is memory-safe and has an excellent concurrency story, but it does not prevent
data races at compile time, its error handling is conventional rather than enforced, and GC pauses
put a floor under tail latency. The margin over Rust is real but smaller than the margin over the
GC'd scripting languages; Rust wins on enforced error handling (Principle VI: "errors MUST be
handled explicitly at every call site") and on documentation enforceability (Principle II).

**Why not TypeScript/Node.js**: it is the popular choice for Discord bots — `discord.js` dominates
by install count — and Principle III explicitly excludes popularity as a justification. It offers no
compile-time data-race or memory guarantees, and its transitive dependency graphs are an order of
magnitude larger than Rust's, which Principle III counts as supply-chain attack surface.

**Why not Python**: the GIL makes the high-fanout gateway workload awkward to scale within a
process, and `discord.py`'s history includes a maintainer-initiated discontinuation and revival — a
bus-factor signal Principle III requires weighing.

**Rust release cadence**: a stable release every six weeks on a fixed train
(forge.rust-lang.org, "Release channel layout"), stable since 1.0 in 2015, with editions providing
opt-in breaking changes without splitting the ecosystem. This is the maturity signal Principle III
demands.

### Discord client library

The Rust ecosystem offers two viable libraries. Measured 2026-09-16:

| | Twilight | Serenity |
|---|---|---|
| Latest stable | 0.17.1 (2025-12-13) | 0.12.5 (2025-12-20) |
| Release line | **Pre-1.0** | **Pre-1.0** |
| Architecture | Modular — separate `-gateway`, `-http`, `-model`, `-cache-inmemory` crates | Monolithic, batteries-included |
| Cache | Opt-in, separate crate | Built in, on by default |
| License | ISC | ISC |
| MSRV | 1.89 | — |
| Repo activity | Last commit 2026-08-30; not archived; 873 stars; 71 open issues | Actively maintained |

**Twilight is selected on architecture.** Three properties matter here and none of them is
popularity:

1. **Opt-in caching.** Serenity caches guild state by default. Twilight makes the cache a separate
   crate you choose to include. Principle I's data-minimization constraint and the Security and
   Platform Constraints section ("collect and retain only the data required by an enabled feature")
   are far easier to satisfy when caching is something you add deliberately rather than something
   you must disable. It also bounds memory growth directly as the guild count rises.
2. **Transitive dependency count.** Principle III requires every direct dependency to justify its
   transitive cost. Pulling `twilight-gateway`, `twilight-http` and `twilight-model` without
   `twilight-cache-inmemory` or `twilight-util` yields a materially smaller graph than a monolithic
   library that brings its framework, cache, and voice support regardless of use.
3. **No imposed framework.** Gaea's command surface is deliberately tiny — FR-041 (002) makes the
   dashboard the sole configuration surface, leaving only a per-feature disable command and the
   temporary-voice owner controls. A command framework would be near-pure overhead.

**Sharding.** Discord requires one gateway shard per 2,500 guilds (Discord Developer Docs,
*Gateway → Sharding*). At this version's target of 25 guilds, Gaea needs a single shard, so
Twilight's multi-shard support is headroom rather than a present requirement.

### Serialization

**Serde 1.0.229**, MIT OR Apache-2.0, MSRV 1.56, last released 2026-07-18. It is on a stable ≥1.0
line with an eight-year compatibility record and is a transitive dependency of Twilight regardless,
so adopting it directly adds no supply-chain surface. It is not an independent decision so much as
an acknowledgement of one already entailed.

Its relevance to Principle I is direct: `#[derive(Deserialize)]` on a typed struct with `deny_unknown_fields`
is the mechanism by which FR-001 (001) — "raw strings MUST NOT cross into the domain" — is enforced
by the compiler rather than by reviewer vigilance.

### Datastore

**PostgreSQL 18.6** (current stable; supported until 2030-11-14 per the PostgreSQL versioning
policy of one major release per year with five years of support). Installed toolchain locally is
already 18.6.

PostgreSQL was not selected generically. Three specific requirements in the specs map onto features
it already has, which is what makes it the engineered choice rather than the default one:

1. **FR-026 (001), exactly-once scheduled delivery across restarts and concurrent instances.**
   `SELECT ... FOR UPDATE SKIP LOCKED` (PostgreSQL docs, *SELECT → The Locking Clause*) is the
   documented idiom for a concurrency-safe work queue. It lets multiple instances drain a schedule
   table without any two claiming the same occurrence, and without an external queue broker. This
   requirement alone rules out datastores lacking transactional row-level claim semantics.
2. **FR-023a/b/c (001), per-guild timezones and explicit daylight-saving rules.** PostgreSQL ships
   the IANA Time Zone Database and implements `timestamptz` with `AT TIME ZONE` conversion
   (PostgreSQL docs, *Date/Time Types*). The non-existent-local-time and ambiguous-local-time cases
   the spec requires are handled by the database's own tz rules, updated with the server, rather
   than by hand-rolled arithmetic — which is precisely where scheduling bugs live.
3. **FR-018 / FR-035 (002), a saved change reaching the running bot within 30 seconds without a
   restart.** `LISTEN`/`NOTIFY` provides transactional change notification, so the bot learns of a
   dashboard write when and only when that write commits. No polling loop, no separate message bus,
   and no window in which the two surfaces disagree.

MVCC gives readers and writers non-blocking concurrency (PostgreSQL docs, *Concurrency Control*),
and ACID transactions are what make FR-019's "no partial change is persisted" enforceable.

**Why not SQLite**: single-writer semantics conflict with concurrent bot and dashboard processes,
and it has no `LISTEN`/`NOTIFY` equivalent.
**Why not MySQL/MariaDB**: `SKIP LOCKED` exists, but the timezone story depends on a separately
loaded tz table rather than being built in, and there is no transactional notification channel.
**Why not a document store**: the data is relational — guild owns settings owns schedules owns
subscriptions — and FR-001 (001)'s cross-guild isolation is a constraint best enforced by foreign
keys and row-level policy, not by application discipline.

---

## Constitutional Compliance

### Compliant

| Requirement | Status |
|---|---|
| Principle II — doc coverage enforced at build | `#![deny(missing_docs)]` fails the build on an undocumented public item, exactly as the principle requires |
| Principle III — license compatibility | Gaea itself is **AGPL-3.0**. Dependencies are MIT / Apache-2.0 / ISC / PostgreSQL License — all permissive and all compatible with incorporation into an AGPL-3.0 work (Apache-2.0 is one-way compatible with GPLv3/AGPLv3). Note that AGPL-3.0 §13 obliges the network-facing dashboard to offer its Corresponding Source to remote users; see FR-055 of spec 002 |
| Principle III — ≥1.0 stable line | Rust ✅ · Tokio 1.53.1 ✅ · Serde 1.0.229 ✅ · PostgreSQL 18.6 ✅ |
| Principle IV — lockfile and integrity | `Cargo.lock` records exact versions and registry checksums; committed |
| Principle IV — SBOM | `cargo sbom` / `cargo cyclonedx` produce SPDX or CycloneDX output |
| Principle IV — advisory scanning | `cargo audit` against RustSec, `cargo deny` for licenses and duplicate graphs |
| Principle VI — explicit error handling | `Result` plus `#[must_use]`; `unwrap`/`expect` bannable by lint |

### DEVIATION — Twilight is pre-1.0, which Principle III prohibits

Principle III states: *"a dependency MUST have a stable (>= 1.0) release line… Pre-1.0 and
unmaintained packages MUST be rejected; if no mature option exists, the capability is implemented
in-house and the decision recorded."*

Twilight 0.17.1 is pre-1.0. So is Serenity 0.12.5. **No ≥1.0 Discord library exists in Rust**, so
this is an ecosystem condition, not a property of the selection. The same is true of much of the
Rust web ecosystem this project will need next — Axum is 0.8.9, SQLx is 0.9.0.

Release cadence is the secondary concern. Twilight's history shows long gaps:

| Version | Released | Gap |
|---|---|---|
| 0.15.4 | 2023-09-10 | — |
| 0.16.0 | 2025-01-12 | 16 months |
| 0.17.0 | 2025-11-08 | 10 months |
| 0.17.1 | 2025-12-13 | 1 month |
| *(none)* | — | **9 months to date** |

The repository is not dormant — last commit 2026-08-30, two weeks before this record — so the
pattern is active development with infrequent releases, not abandonment. For a library tracking a
continuously changing platform API, that still means periods where upstream Discord changes are in
`main` but not in a published crate.

**RESOLVED 2026-09-16** by [ADR-0002](0002-pre-1.0-dependency-policy.md): Principle III was amended
(constitution v1.0.0 → v1.1.0) so that `>= 1.0` is a tie-breaking preference rather than an absolute
bar, and a pre-1.0 dependency may be adopted when six stated conditions hold — including the
isolation boundary below, which is now binding architecture rather than advice. The analysis that
led there is retained:

**Three resolutions were available:**

1. **Amend Principle III** to permit a pre-1.0 dependency under stated conditions — an actively
   maintained repository, a permissive license allowing a fork, isolation behind an internal
   boundary, and a named owner responsible for tracking it. This is honest about the Rust
   ecosystem's actual maturity conventions, where 0.x lines are routinely production-grade.
   Requires a MINOR constitution bump.
2. **Implement the Discord client in-house**, which Principle III explicitly contemplates when no
   mature option exists. Gaea uses a narrow slice of the Discord API — one gateway connection, a
   handful of REST endpoints, interaction signature verification. This is genuinely feasible and
   genuinely expensive, and it moves the maintenance burden of tracking a moving platform API onto
   this project permanently.
3. **Record a standing deviation** under the Governance compliance-review clause. Weakest option:
   the principle says MUST, and a standing exception to a MUST without amendment erodes the document.

**Option 1 was chosen.** The isolation mitigation below applies regardless and is now required by
amended Principle III condition (d) for every pre-1.0 dependency, not only for Twilight.

### Mandatory mitigation

All Discord platform access MUST sit behind an internal boundary owned by this project — a trait
defining the operations Gaea actually needs (send message, create voice channel, move member, delete
channel, verify interaction signature, subscribe to gateway events). No Twilight type may appear in
domain logic, in the dashboard, or in the datastore layer.

This is worth doing on its own merits and is not merely deference to the constitution: it makes the
library replaceable, makes a fork viable if upstream stalls, and makes the domain testable without a
live gateway — which is what the deny-path test coverage in FR-005 (001, Principle V) requires.

### Currency violation, immediate

The installed toolchain is **rustc 1.93.0 (2026-01-19)**; current stable is **1.98.1 (2026-09-01)**.
That is roughly eight months stale, against Principle IV's 30-day ceiling. The toolchain must be
updated and pinned via `rust-toolchain.toml` before implementation starts, and the 30-day staleness
assertion must be part of CI from the first commit, not retrofitted.

Note that Twilight's MSRV is 1.89, so the update is unblocked.

---

## Consequences

### Positive

- An entire class of vulnerability — the class responsible for ~70% of CVEs in the cited
  large-codebase studies — is eliminated at compile time rather than tested for.
- Principle II's documentation gate is enforceable by the compiler, not by review discipline.
- Principle VI's "errors MUST be handled explicitly at every call site" is enforceable by the type
  system rather than by convention.
- No GC pauses beneath the SC-002/SC-003 latency targets.
- Three specific spec requirements (exactly-once delivery, DST-correct scheduling, sub-30-second
  config propagation) are served by PostgreSQL features rather than by application code, removing
  the three most likely sources of subtle correctness bugs in this system.
- Single static binary deployment; no runtime interpreter or VM to patch separately.

### Negative — accepted

- **Development velocity is lower than the GC'd alternatives**, particularly early. Borrow-checker
  friction is a real cost paid for the guarantees above.
- **The Rust web ecosystem is less batteries-included** than Django or Rails. Spec 002 requires
  session management, request-forgery defense, CSP, and template rendering (FR-002, FR-004, FR-028);
  in Rust these are assembled from parts, each needing its own review. This is the largest single
  risk this decision creates, and it lands on the half of the project with the most security
  surface.
- **The Discord library is pre-1.0 and releases irregularly.** Mitigated by the isolation boundary
  above, unresolved until Principle III is settled.
- **A smaller hiring and contribution pool** than the popular alternatives. Principle III
  deliberately treats this as not a selection criterion, but it is a real consequence.
- **Compile times** will slow the edit-test loop; expect to invest in workspace splitting and
  caching.

### Neutral

- PostgreSQL requires an operator to run and back up a database server. Consistent with the
  self-hosted posture already assumed, and with the operator responsibilities recorded in FR-039
  (002) for TLS and reverse proxy.

---

## Follow-up ADRs Required

This record decides four layers. **It does not decide everything needed to plan either spec**, and
in particular spec 002 cannot proceed without ADR-0003 and ADR-0004.

All follow-up decisions identified here were taken on 2026-09-16 and are recorded:

| ADR | Decision | Status |
|---|---|---|
| [0002](0002-pre-1.0-dependency-policy.md) | Pre-1.0 dependency policy — Principle III amended | Accepted |
| [0003](0003-process-topology-and-interaction-transport.md) | Two binaries, one database; interactions over the gateway | Accepted |
| [0004](0004-data-access-and-migrations.md) | SQLx with compile-time-checked queries; separate migration binary | Accepted |
| [0005](0005-dashboard-http-stack-and-rendering.md) | Axum + Askama; server-rendered with targeted enhancement | Accepted |
| [0006](0006-session-and-identity.md) | Server-side sessions in PostgreSQL; Discord OAuth2 with PKCE | Accepted |
| [0007](0007-external-alert-transports.md) | EventSub webhooks + WebSub push, with a reconciliation sweep | Accepted |
| [0008](0008-secrets-and-configuration.md) | File-mounted secrets read at startup | Accepted |
| [0009](0009-observability.md) | tracing for logs and spans; Prometheus scrape for metrics | Accepted |

ADR-0007 deserved the emphasis it was given: measurement showed Twitch's EventSub WebSocket
transport caps the entire deployment at roughly ten streamers (`max_total_cost` of 10), which would
have made SC-005 unreachable had it been chosen by default.

---

## Verification Record

Observed 2026-09-16 from crates.io API, static.rust-lang.org, api.github.com, endoflife.date:

```
rustc stable      1.98.1 (48a229cea 2026-09-01)   [installed: 1.93.0 — STALE]
tokio             1.53.1   2026-07-20   MIT                  MSRV 1.71
serde             1.0.229  2026-07-18   MIT OR Apache-2.0    MSRV 1.56
twilight-gateway  0.17.1   2025-12-13   ISC                  MSRV 1.89
twilight-http     0.17.1   2025-12-13   ISC
twilight-model    0.17.1   2025-12-13   ISC
serenity          0.12.5   2025-12-20   ISC        (rejected — see Options Considered)
PostgreSQL        18.6                  PostgreSQL License   EOL 2030-11-14  [installed: 18.6]
twilight-rs/twilight  last commit 2026-08-30, not archived, 873 stars, 71 open issues
```

Per Principle IV these are a point-in-time snapshot. CI asserts currency continuously; this table is
evidence for the decision, not a substitute for that assertion.
