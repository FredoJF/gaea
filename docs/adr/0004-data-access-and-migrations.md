# ADR-0004: Data Access Layer and Schema Migrations

**Status**: Accepted · **Date**: 2026-09-16

## Context

Three requirements depend on specific SQL rather than on generic persistence:

- **FR-026 (001)** — each scheduled instant delivered exactly once, across restarts, redeployments
  and concurrent instances. The documented PostgreSQL idiom is
  `SELECT ... FOR UPDATE SKIP LOCKED` (PostgreSQL docs, *SELECT → The Locking Clause*).
- **FR-023a/b/c (001)** — per-guild timezones with explicit rules for non-existent and ambiguous
  local times, served by `timestamptz` and `AT TIME ZONE` against PostgreSQL's bundled IANA tz data.
- **FR-001 (001)** — cross-guild isolation, best enforced by foreign keys and row-level policy.

Measured 2026-09-16: sqlx 0.9.0 (2026-05-21, pre-1.0) · diesel 2.3.13 (2026-09-04, >= 1.0) ·
sea-orm 2.0.3 (2026-09-13, >= 1.0) · tokio-postgres 0.7.18 (2026-06-12, pre-1.0).

## Decision

**SQLx with compile-time-checked queries.** Queries are written as literal SQL and verified against
the real schema at build time; a query that does not match the database fails the build.

**Migrations are plain versioned `.sql` files applied by a dedicated migration binary** using a
separate, privileged database account, as a deliberate deployment step.

## Rationale

The three requirements above are expressed most clearly, and reviewed most safely, as literal SQL.
`SKIP LOCKED` and `AT TIME ZONE` escape any DSL anyway; writing them as SQL that the compiler checks
against the schema gives both readability during security review and build-time verification.

SQLx's `query!` macros bind parameters rather than interpolating them, so injection is prevented by
construction rather than by discipline — relevant to Principle I's boundary-validation rule.

A dedicated migration binary satisfies the constitution's requirement that schema migration use a
separate, privileged account from the one the application runs as, and avoids the startup race that
ADR-0003's two-process topology would otherwise create.

## Alternatives Considered

- **Diesel** — on a `>= 1.0` line and very actively released, which under amended Principle III is a
  genuine tie-breaker advantage. Rejected because async support lives in `diesel-async`, itself
  pre-1.0, so the advantage largely evaporates in an async codebase — and the SQL this project needs
  has to escape the DSL regardless.
- **SeaORM** — `>= 1.0` and async, but a full ORM built *on top of* SQLx, so it pulls SQLx
  transitively while adding an abstraction over exactly the SQL that needs to stay legible.
- **tokio-postgres plus a pool** — thinnest graph, but no compile-time schema verification, so a
  drifted migration becomes a production runtime failure instead of a build failure.
- **Migrate at service startup** — rejected: requires the application account to hold schema
  privileges, which the constitution forbids, and races between the two processes.
- **Refinery** — adds a pre-1.0 dependency for capability SQLx already provides.

## Constitutional Compliance (amended Principle III, conditions 1-6)

1. A `>= 1.0` alternative exists (Diesel, SeaORM) but not of comparable merit for this workload —
   see Alternatives.
2. sqlx released 2026-05-21, within the activity window. Re-check required in CI.
3. MIT OR Apache-2.0 — forking permitted.
4. Data access is confined to repository types owned by this project; no SQLx type appears in domain
   logic.
5. Owner: project maintainer.
6. Cadence recorded above.

## Consequences

- The build requires either a reachable development database or a committed offline query cache.
  The offline cache must be committed and kept current, or CI cannot build — this is a real
  day-to-day cost of the compile-time checking.
- Migrations are ordinary reviewable SQL, which suits a security-first project.
- Deployment gains an ordered step: migrate, then start services.
- Query changes and schema changes must land together, since the build enforces their agreement.
