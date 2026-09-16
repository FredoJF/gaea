# ADR-0003: Process Topology and Discord Interaction Transport

**Status**: Accepted · **Date**: 2026-09-16

## Context

SC-014 (002) requires the bot to continue operating all configured features normally while the
dashboard is entirely unavailable, verified by fault injection. FR-030 (002) requires the dashboard
to remain available to other guilds when any one guild's dependency fails. FR-040 (002) puts the
dashboard on the public internet facing continuous hostile traffic, while the bot process needs no
inbound connectivity at all.

Separately, Discord delivers slash command invocations either over the gateway connection
(`INTERACTION_CREATE`) or by HTTP POST to a public endpoint the application registers.

## Decision

**Two binaries, one PostgreSQL instance.** A bot process and a web process, deployed and restarted
independently, coordinating through the shared database and `LISTEN`/`NOTIFY`. Only the web process
is reachable from the network.

**Interactions arrive over the gateway.** The bot process handles `INTERACTION_CREATE`. No HTTP
interaction endpoint is registered.

## Rationale

The topology makes SC-014 structural rather than aspirational. A panic, a memory leak, a restart, or
a deliberate shutdown of the hostile-traffic-facing process has no path to the gateway connection,
because they share no address space. In a single process, fault injection would fail SC-014 by
construction.

The interaction transport follows from FR-042 (002): the emergency disable command must work
*without requiring the dashboard to be reachable*. Routing interactions through the public web
process would break that command in precisely the situation it exists for. Gateway delivery also
keeps the bot entirely off the public internet and means Principle I's Ed25519 interaction-signature
requirement never engages — there is no endpoint to forge a request to.

`LISTEN`/`NOTIFY` satisfies FR-018/FR-035 (002)'s 30-second propagation transactionally: the bot
learns of a dashboard write when and only when that write commits, with no polling loop and no
window in which the two surfaces disagree.

## Alternatives Considered

- **One binary, both roles** — simplest, and rejected for the SC-014 coupling above.
- **One binary, two runtime modes** — one build, one dependency graph, separate processes. Rejected
  because the web half's dependencies would be linked into the bot binary, enlarging the attack
  surface of the process that holds the bot token.
- **A third process for external-platform work** — deferred, not rejected. ADR-0007's reconciliation
  sweep is the workload that would justify it; the boundary is drawn so that split stays cheap.
- **HTTP interactions on the web process, or on a third process** — rejected per FR-042 above.

## Consequences

- Two deployables, two service units, two sets of logs. Operational cost accepted.
- Schema migrations must be a separate deliberate step, since two processes starting together would
  otherwise race. See [ADR-0004](0004-data-access-and-migrations.md).
- Both processes need the database credential; only the web process needs the Discord OAuth2 client
  secret; only the bot process needs the bot token. Secret scoping per process is possible and is
  required by [ADR-0008](0008-secrets-and-configuration.md).
- Shared code (domain types, data access, the Discord boundary from ADR-0002) lives in library
  crates consumed by both binaries — a Cargo workspace.
- At the SC-009 target of 1,000 guilds Discord requires a single gateway shard (Discord Developer
  Docs, *Gateway → Sharding*: one shard per 2,500 guilds), so the bot process is a singleton. Running
  two instances would duplicate every event; this must be prevented operationally and guarded in
  code.
