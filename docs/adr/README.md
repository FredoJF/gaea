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
| [0010](0010-development-and-delivery-toolchain.md) | Development and Delivery Toolchain | Accepted |

## Selected stack

| Layer | Selection | Version verified 2026-09-16 |
|---|---|---|
| Language / toolchain | Rust | 1.98.1 (installed and current) |
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

## Project licence

Gaea is **AGPL-3.0**. All dependencies are permissive (MIT, Apache-2.0, ISC, PostgreSQL License) and
compatible with incorporation into an AGPL-3.0 work. §13 obliges the network-facing dashboard to
offer its Corresponding Source to remote users — a functional requirement, recorded as FR-055 and
FR-056 in [spec 002](../../specs/002-web-management-dashboard/spec.md).

## Closed action items

1. ~~Update the Rust toolchain.~~ **Closed 2026-09-16** — updated to 1.98.1, which is latest stable.
   Pinning via `rust-toolchain.toml` is a scaffolding task so the version is asserted, not merely
   current on one machine.
2. ~~Confirm `tracing` repository activity.~~ **Closed 2026-09-16** — last commit 2026-05-30, 109
   days. This failed the original 90-day window, and the response was to correct the threshold to
   180 days (constitution v1.1.1) rather than waive the condition. See
   [ADR-0002](0002-pre-1.0-dependency-policy.md).
3. ~~Confirm the Twitch EventSub webhook cost ceiling.~~ **Closed 2026-09-16** — V1's ceilings were
   lowered so the figure is no longer depended upon. Confirming it is now a precondition for
   *raising* the deployment ceiling, not for shipping. See
   [ADR-0007](0007-external-alert-transports.md).
4. ~~Record the internal Discord boundary.~~ **Closed** — specified in
   [contracts/discord-boundary.md](../../specs/001-guild-automation-suite/contracts/discord-boundary.md).

## Open action items

1. **Measure the YouTube WebSub lease duration** at implementation time. The hub chooses the lease
   it grants, so renewal must be scheduled from the `lease_seconds` in the confirmation and never
   from a constant. A lapsed lease announces nothing — see
   [ADR-0007](0007-external-alert-transports.md).
