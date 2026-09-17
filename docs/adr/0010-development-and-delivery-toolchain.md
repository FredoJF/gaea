# ADR-0010: Development and Delivery Toolchain

**Status**: Accepted · **Date**: 2026-09-16

## Context

Before implementation begins, four operational decisions were outstanding. None is architecturally
deep, but each shapes a large part of the task list and two of them touch constitutional
obligations.

The repository is live at `FredoJF/gaea` on GitHub under **AGPL-3.0**, with no CI configuration and
no Cargo workspace yet.

## Decisions

### Test database

**`#[sqlx::test]` against a developer-provided PostgreSQL.** SQLx's harness creates and drops a
fresh database per test, giving per-test isolation without adding a dependency — it is the tool
already chosen for queries in [ADR-0004](0004-data-access-and-migrations.md).

*Rejected*: testcontainers — hermetic and identical everywhere, but makes Docker a hard dependency
of running any test. A shared database with transactional rollback — fastest, but this feature uses
sequences, advisory locks and `LISTEN`/`NOTIFY`, none of which roll back, so tests would interfere
in exactly the areas that matter most. Both strategies together — a failure reproducing in only one
of two paths is worse than either path alone.

*Consequence*: a running PostgreSQL is a prerequisite of any test run, CI included. CI therefore
provisions one as a service container.

### Continuous integration

**GitHub Actions**, matching the repository remote. The gates are not a matter of taste — they are
the mechanism by which Principles II, IV and V are enforced rather than aspired to:

| Gate | Principle |
|---|---|
| Build with zero compiler and linter warnings | V |
| Documentation coverage for all public items | II |
| `cargo audit` (RustSec) and `cargo deny` (licences, duplicate graphs) | I, IV |
| No pin more than 30 days behind latest stable | IV |
| Secret scanning over diff and history | I |
| Full test suite, no skipped or quarantined tests | V |

### Operator configuration CLI

**A `gaea-admin` binary**, run on the host by the operator.

*Context*: the dashboard (spec 002) does not exist yet, so there is otherwise no way to configure
the bot in order to run or demonstrate it.

*The FR-041 question, answered explicitly*: FR-041 makes the dashboard the sole configuration
surface. That governs the people who reach the bot through Discord or the web — owners,
administrators, managers, viewers. The host operator already holds shell access and the database
credential, and therefore already has unconditional authority over every setting; operator tooling
adds no authorization surface and creates no second path to keep correct. This reading is now
recorded as FR-041a in spec 002 rather than left implicit.

*Rejected*: raw SQL seed scripts — they bypass every write-time validation the spec requires, so
testing would run against configurations the real system would refuse. Test fixtures only — the bot
could never be exercised against a real guild until 002 ships, making the quickstart guide unusable.
Building 002's configuration pages first — no throwaway work, but it front-loads the entire web
stack before a single bot feature is proven.

*Consequence*: `gaea-admin` outlives the dashboard as the recovery path for when the dashboard is
down, which is also when FR-042's emergency disable matters. It must apply the same validation the
dashboard does, or it becomes a way to write configurations the bot cannot honour.

### Delivery order

**Scaffolding, then CI gates, then container, then features in spec priority order (P1–P5).**

Feature-first was rejected on the grounds that the gates above are what make the constitution
enforceable; retrofitting them means the earliest and least-reviewed merges are the ones that never
faced them.

## Consequences

- Four binaries in the workspace: `gaea-bot`, `gaea-migrate`, `gaea-admin`, `gaea-web`.
- `gaea-admin` must share the validation layer with the dashboard rather than reimplementing it,
  which pushes that validation into `gaea-domain` where both can reach it — a constraint worth
  having anyway.
- CI needs a PostgreSQL service and both database roles, privileged and DML-only, so the migration
  path is exercised on every run rather than only at deployment.
- AGPL-3.0 obliges the network-facing dashboard to offer its Corresponding Source to remote users
  (§13). This is a functional requirement of the product, recorded as FR-055 and FR-056 in spec 002,
  not a packaging detail — and it is the reason an unauthenticated, discoverable route exists on a
  dashboard that otherwise reveals nothing before sign-in.
