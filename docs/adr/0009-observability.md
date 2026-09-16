# ADR-0009: Observability — Logging, Tracing, and Metrics

**Status**: Accepted · **Date**: 2026-09-16

## Context

Principle VI requires structured logging with a correlation identifier propagated across gateway
event, command execution, and outbound API call; redaction of secrets and message content enforced
by a type-level or serializer-level mechanism rather than by developer discipline; an immutable
audit record for every privileged action; health and readiness endpoints; and metrics for gateway
connection state, event processing latency, command error rate, and Discord rate-limit consumption.

Measured 2026-09-16: tracing 0.1.44 (2025-12-18, pre-1.0, 851M downloads) · metrics 0.24.6
(2026-05-13, pre-1.0) · opentelemetry 0.32.0 (2026-05-08, pre-1.0).

## Decision

**Structured logs and spans via `tracing`; metrics exposed on a Prometheus scrape endpoint.**

## Rationale

`tracing`'s span model is a direct fit for Principle VI's correlation requirement: a span opened when
a gateway event arrives carries its identifier through command execution and into the outbound API
call without that identifier being threaded through every function signature by hand.

Pull-based metrics mean the application holds no credentials for and no hard dependency on a
monitoring backend — it exposes a page and nothing more. For a self-hosted deployment where the
operator already runs their own monitoring, this is the lightest arrangement that satisfies the
requirement, and it adds no outbound network dependency to either process.

The four metrics Principle VI names are treated as a floor, not a list to stop at. Discord
rate-limit consumption in particular is a leading indicator: FR of 001's platform-compliance section
requires a 429 response to be treated as a defect in the client's own limiter, which is only
detectable if consumption is measured continuously.

## Alternatives Considered

- **OpenTelemetry OTLP** — vendor-neutral, with correlation across traces, metrics and logs built
  in, which suits the correlation requirement well. Rejected for now as heavier, and because the
  collector becomes a runtime dependency to deploy and secure. `tracing` can export to OTLP later
  without changing instrumentation, so this is deferred rather than foreclosed.
- **Prometheus plus OTLP traces** — best signal coverage; rejected as two exporters, two
  configurations and two dependency sets to audit for a single-operator deployment.
- **Structured logs only** — would not satisfy Principle VI, which names four metrics explicitly.

## Constitutional Compliance (amended Principle III, conditions 1-6)

`tracing` and `metrics` are pre-1.0. (1) No `>= 1.0` alternative of comparable merit exists;
`tracing` is the ecosystem standard at 851M downloads and is already a transitive dependency of
Tokio-based libraries. (2) tracing released 2025-12-18 — **outside the 90-day window**, so
repository activity must be confirmed and recorded before adoption, and re-checked in CI.
(3) MIT permits forking. (4) Instrumentation is confined to a project-owned facade so the backend can
be replaced. (5) Owner: project maintainer. (6) Cadence recorded above.

## Consequences

- The metrics endpoint is an inbound surface. It must not be exposed publicly alongside the
  dashboard, and it must expose no guild-identifying data — metric labels are a classic accidental
  disclosure path and must be reviewed as carefully as log output.
- Redaction is type-level: identifiers that may be logged and content that may not are distinct
  types, so Principle VI's redaction requirement cannot be violated by an ordinary formatting call.
- Health and readiness are distinct: readiness for the bot process means a live gateway connection,
  not merely a running process.
- The audit record required by Principle VI lives in the database, not in the log stream, because
  FR-027 (002) requires it to be immutable and queryable by the dashboard.
- `tracing`'s release date falls outside the amended activity window. This must be checked, not
  assumed, before it is adopted — and it is the first live test of whether the ADR-0002 conditions
  are actually enforced or merely written down.
