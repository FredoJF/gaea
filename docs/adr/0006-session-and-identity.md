# ADR-0006: Session and Identity Handling

**Status**: Accepted · **Date**: 2026-09-16

## Context

FR-001 (002) requires authentication through the user's Discord account with no password handled or
stored. FR-002 requires sessions terminated at sign-out, after inactivity, and at an absolute
maximum age. **FR-003 requires server-side invalidation at sign-out such that a replayed session
identifier grants no access.** FR-008 bounds cached authority at 5 minutes. FR-004 requires
state-changing requests to demonstrably originate from the dashboard.

Measured 2026-09-16: oauth2 5.0.0 (2025-01-21, >= 1.0) · tower-sessions 0.15.0 (2026-02-01, pre-1.0).

## Decision

**Server-side sessions stored in PostgreSQL.** The cookie carries only an opaque, high-entropy
random identifier; all session state lives in a table. Identity is established through Discord's
OAuth2 authorization code flow with PKCE.

## Rationale

FR-003 decides this. A stateless signed or encrypted cookie cannot be revoked — once issued it is
valid until it expires, wherever and by whomever it is replayed. Stateless cookies were therefore
not a viable option, only a documented non-starter.

With session rows in the database, FR-002's three termination conditions are ordinary column
comparisons, FR-003's sign-out is a row deletion, and FR-008's 5-minute authority bound is a
timestamp on the cached authority assessment. No new operational dependency is introduced: ADR-0003
already establishes one shared PostgreSQL instance.

Session identifiers are generated from a CSPRNG with at least 128 bits of entropy, per Principle I.

## Alternatives Considered

- **Stateless signed cookies** — fails FR-003 outright.
- **Redis-backed sessions** — fast with native expiry, and keeps session writes off the primary
  database. Rejected: a second datastore to run, secure, back up and patch, for a workload
  PostgreSQL handles comfortably at SC-009's scale.
- **Signed cookie plus a revocation deny list** — satisfies FR-003 with fewer session reads.
  Rejected: two mechanisms to maintain, and the deny list is itself state — most of the cost of a
  session store with more ways to get it wrong.

## Consequences

- A session read on every authenticated request. At SC-009's 100 concurrent users this is
  negligible; if it ever is not, a short-lived in-process cache is possible but must never exceed
  FR-008's 5-minute authority bound.
- Expired sessions must be reaped; a periodic sweep is required, not optional, or the table grows
  without bound.
- Signing out on one device can terminate that device's session precisely, because sessions are
  individually addressable.
- The Discord client secret is needed only by the web process, supporting the per-process secret
  scoping in [ADR-0008](0008-secrets-and-configuration.md).
- Cookie attributes, the forgery defense satisfying FR-004, and the trusted-proxy handling from
  FR-037 are implementation obligations of this decision and must be covered by the deny-path tests
  Principle V requires.
