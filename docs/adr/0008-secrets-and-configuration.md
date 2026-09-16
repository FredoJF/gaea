# ADR-0008: Secret Injection and Configuration Loading

**Status**: Accepted · **Date**: 2026-09-16

## Context

Principle I requires secrets — bot token, Discord client secret, signing keys, database credentials,
Twitch and YouTube platform credentials — to be injected at runtime from the environment or a secret
manager, and treats a secret committed to version control as a release-blocking incident. FR-039
(002) requires the application to fail to start with an explanatory error rather than run insecurely
when security-relevant configuration is absent or contradictory.

## Decision

**Secrets are mounted as files whose paths are named in configuration, and read once at startup.**
Non-secret configuration is ordinary configuration. Environment variables are not used to carry
secret material in any build profile, including development.

## Rationale

The process environment is a poor container for secrets. It is readable by anything that can inspect
the process, it is inherited by every child process, and it routinely surfaces in crash reports,
container inspection output, and logs that dump the environment during debugging. Files can be
permission-restricted, are not inherited, and do not appear in `/proc/<pid>/environ`.

This works directly with the mechanisms a self-hosting operator already has — Docker secrets,
Kubernetes secrets, and systemd `LoadCredential` all present secrets as files — which suits the
operator-responsibility posture already established in FR-039 (002) for TLS and reverse proxy.

A development-only environment-variable path was considered and rejected: it would create two code
paths through the most security-sensitive loading logic in the application, and the weaker one is
the one developers exercise daily. A single path, exercised identically everywhere, is worth the
minor local inconvenience of writing a file.

## Alternatives Considered

- **Environment variables** — conventional twelve-factor and simplest to deploy; rejected on the
  exposure properties above.
- **External secret manager** — strongest posture and the best rotation story. Rejected for now as
  disproportionate for a self-hosted deployment, and because it makes the manager a hard startup
  dependency for both processes. Not foreclosed: because secrets are read through one abstraction at
  startup, adding a manager later is a change in one place.
- **Files with an environment fallback for development** — rejected per the two-code-paths argument.

## Consequences

- Secrets are loaded once at startup into a type that does not implement the standard display or
  debug formatting, so a secret cannot reach a log through an ordinary formatting call. This is the
  type-level redaction Principle VI requires.
- Both processes need the database credential; **only the bot process needs the Discord bot token**,
  and **only the web process needs the Discord OAuth2 client secret** and the platform callback
  secrets. ADR-0003's two-binary topology makes this scoping enforceable rather than notional, and
  each process must be given only what it needs.
- Rotation requires replacing a file and restarting the affected process. Acceptable; a
  bot-token-compromise rotation is already required by the constitution to precede root-cause
  analysis, so it is an operational path that must be exercised anyway.
- Startup validates that every required secret is present and well-formed, and refuses to start
  otherwise, satisfying FR-039. Absence must be a loud failure, never a silent default.
- Secret file paths are configuration and may appear in logs; secret contents must not. These must
  be distinct types so the distinction cannot be lost by accident.
