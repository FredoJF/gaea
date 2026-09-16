# Architecture Decision Records

Principle II of the [constitution](../../.specify/memory/constitution.md) requires every
architecturally significant decision to be recorded here with context, options considered with
measured or cited evidence, decision, and consequences.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-language-runtime-and-datastore.md) | Language, Discord Library, Serialization, and Datastore | Accepted |
| [0002](0002-pre-1.0-dependency-policy.md) | Pre-1.0 Dependency Policy | Accepted |
| [0003](0003-process-topology-and-interaction-transport.md) | Process Topology and Discord Interaction Transport | Accepted |
| [0004](0004-data-access-and-migrations.md) | Data Access Layer and Schema Migrations | Accepted |
| [0005](0005-dashboard-http-stack-and-rendering.md) | Dashboard HTTP Stack and Rendering | Accepted |
| [0006](0006-session-and-identity.md) | Session and Identity Handling | Accepted |
| [0007](0007-external-alert-transports.md) | Twitch and YouTube Alert Transports | Accepted |
| [0008](0008-secrets-and-configuration.md) | Secret Injection and Configuration Loading | Accepted |
| [0009](0009-observability.md) | Observability — Logging, Tracing, and Metrics | Accepted |

## Selected stack

| Layer | Selection | Version verified 2026-09-16 |
|---|---|---|
| Language / toolchain | Rust | 1.98.1 — **installed 1.93.0, must be updated** |
| Async runtime | Tokio | 1.53.1 |
| Discord client | Twilight (modular crates) | 0.17.1 |
| Serialization | Serde | 1.0.229 |
| Datastore | PostgreSQL | 18.6 |
| Data access | SQLx, compile-time-checked queries | 0.9.0 |
| HTTP framework | Axum | 0.8.9 |
| Templating | Askama | 0.16.1 |
| Logging / spans | tracing | 0.1.44 |
| Metrics | Prometheus scrape endpoint | — |

Every version above is a point-in-time observation. Principle IV requires CI to assert currency
continuously — no pin more than 30 days behind latest stable, no advisory in the graph.

## Open action items

1. **Update the Rust toolchain.** Installed 1.93.0 (2026-01-19) against stable 1.98.1 (2026-09-01) —
   roughly 8 months stale, against Principle IV's 30-day ceiling. Pin via `rust-toolchain.toml`
   before implementation begins. Twilight's MSRV is 1.89, so nothing blocks the update.
2. **Confirm `tracing` repository activity.** Its last release (2025-12-18) falls outside the 90-day
   activity window that amended Principle III condition (b) requires. Confirm and record before
   adoption — see [ADR-0009](0009-observability.md).
3. **Confirm the Twitch EventSub webhook cost ceiling** and the WebSub lease duration against
   current documentation. Both are inputs to FR-042b's deployment-wide subscription ceiling — see
   [ADR-0007](0007-external-alert-transports.md).
4. **Record the internal Discord boundary** required by amended Principle III condition (d) as part
   of the implementation plan, not as an afterthought.
