# ADR-0005: Dashboard HTTP Stack and Rendering

**Status**: Accepted · **Date**: 2026-09-16

## Context

Spec 002 requires a publicly reachable management dashboard meeting WCAG 2.2 Level AA (FR-031),
usable on a 375-pixel screen (FR-032), translation-ready with user-visible strings held outside the
logic (FR-046), rendering all guild-derived text inertly (FR-028), with live channel and role
pickers (FR-016, FR-033), template preview (FR-020), and concurrent-edit detection (FR-021). It
faces continuous hostile unauthenticated traffic (FR-040) and must derive client addresses through a
trusted upstream proxy (FR-037).

Measured 2026-09-16: axum 0.8.9 (2026-04-14, pre-1.0) · actix-web 4.15.0 (2026-08-21, >= 1.0) ·
poem 3.1.12 (2025-07-28, >= 1.0) · rocket 0.5.1 (2024-05-23, pre-1.0) · askama 0.16.1 (2026-09-04,
pre-1.0) · minijinja 2.24.0 (2026-09-15, >= 1.0) · tera 2.4.0 (2026-09-11, >= 1.0) · maud 0.27.0
(2025-02-02, pre-1.0).

## Decision

**Axum** for the HTTP surface, **Askama** for rendering, **server-rendered HTML with targeted
JavaScript** only where the spec demands interactivity.

## Rationale

**Axum.** It is built directly on hyper and tower — the same HTTP stack Twilight already pulls in —
so the dependency graph carries one HTTP implementation rather than two. Principle III counts
transitive dependency count as supply-chain surface, and this is the largest single reduction
available. Tower middleware also gives rate limiting (FR-029) and trusted-proxy client-address
extraction (FR-037) as composable layers rather than bespoke code.

The honest cost: actix-web is on a `>= 1.0` line and was released more recently (2026-08-21 against
Axum's 2026-04-14), and under amended Principle III that is a real tie-breaker advantage. It was
outweighed by the single-HTTP-stack argument, and the decision is recorded here so it can be
revisited if Axum's cadence slips further.

**Askama.** Templates are checked at compile time against the types passed to them, so a renamed
field is a build failure rather than a broken page a user discovers. It auto-escapes by default,
which is how FR-028's inert-rendering requirement is enforced structurally rather than by
remembering to escape. Templates remain separate files, so translation and design work stay out of
Rust source, supporting FR-046.

**Server-rendered with targeted enhancement.** Keeping authorization in one place is the point: a
JSON API would require FR-009's per-request authority check to be correct independently in two
places, and FR-011c's server-side viewer enforcement likewise. Server-rendered HTML is also the
strongest starting point for both WCAG 2.2 AA and translation. JavaScript is added only where the
spec requires it — searchable pickers (FR-033), template preview (FR-020) — and every such control
must have a working non-JavaScript path, because FR-011c forbids relying on controls being hidden.

## Alternatives Considered

- **actix-web** — see the tradeoff above.
- **Poem** — `>= 1.0` but 14 months since release and a far smaller contributor base; a weak
  maintenance signal for the component facing hostile traffic.
- **Rocket** — 28 months since release and still pre-1.0. Fails the amended Principle III activity
  condition.
- **MiniJinja / Tera** — both `>= 1.0` and actively released, which is a genuine advantage.
  Rejected because template errors surface at runtime in front of a user, against this project's
  consistent preference for failing at build time.
- **Maud** — compile-time and escaping by construction, but markup lives in Rust source, which is
  the worst starting point for FR-046. Also 19 months since its last release.
- **Single-page app with a JSON API** — rejected: doubles the authorization surface and adds a
  JavaScript build chain and dependency graph to audit.
- **Pure server-rendered, no JavaScript** — smallest surface and seriously considered. Rejected
  because preview and large-guild pickers become round-trips that make SC-002's 30-second edit
  target hard to hit.

## Constitutional Compliance (amended Principle III, conditions 1-6)

Axum and Askama are both pre-1.0. (1) `>= 1.0` alternatives exist and were rejected on merit above;
(2) both released within 90 days of this record — Askama 2026-09-04, Axum 2026-04-14, the latter
needing watching; (3) MIT and MIT OR Apache-2.0 permit forking; (4) HTTP types are confined to the
web crate's handler layer and templates to its rendering layer — neither appears in domain logic;
(5) owner: project maintainer; (6) cadence recorded above.

## Consequences

- One authorization path, exercised by every request. This is the main security benefit.
- No JavaScript build toolchain in the default path; any added must be justified and audited.
- Axum's release cadence is the thing to watch. If it stalls past the 90-day activity window,
  revisit against actix-web — the handler layer is the only code that would change.
- Askama's compile-time checking means template and handler changes land together.
- Every interactive control needs a non-JavaScript fallback, which is extra work and is also what
  makes FR-031's keyboard operability and FR-011c's server-side enforcement achievable.
