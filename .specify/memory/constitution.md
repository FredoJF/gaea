<!--
SYNC IMPACT REPORT (temporary scratch material — remove before committing the amended file)

Version change: TEMPLATE (unfilled scaffold) → 1.0.0
Bump rationale: Initial ratification. All placeholder tokens replaced with concrete,
enforceable governance. No prior version existed, therefore no backward-incompatible
redefinition occurred; semantic versioning starts at 1.0.0.

Modified principles (placeholder → concrete):
  [PRINCIPLE_1_NAME] → I. Security-First by Default (NON-NEGOTIABLE)
  [PRINCIPLE_2_NAME] → II. Total Documentation (NON-NEGOTIABLE)
  [PRINCIPLE_3_NAME] → III. Selection by Engineering Merit, Not Popularity
  [PRINCIPLE_4_NAME] → IV. Current, Pinned, and Verified Dependencies
  [PRINCIPLE_5_NAME] → V. Proven Correctness Before Merge
  (added)           → VI. Observability and Auditability

Added sections:
  ## Security and Platform Constraints   (was [SECTION_2_NAME])
  ## Development Workflow and Quality Gates  (was [SECTION_3_NAME])
  ### VI. Observability and Auditability (sixth principle beyond the 5-principle scaffold)

Removed sections: none.

Follow-up TODOs:
  - TODO(TECH_STACK_DECISION): Principle III mandates a recorded, evidence-based language and
    runtime selection. No ADR exists yet. The first ADR (ADR-0001) MUST be authored before the
    first line of application code is written.
  - Principle IV deliberately reinterprets the stated "always latest stable" requirement as
    "lockfile-pinned exact versions, held no more than 30 days behind latest stable, after a
    72-hour publication cooldown." A floating "latest" resolver directive is incompatible with
    reproducible builds and with Principle I; see the rationale in Principle IV. Confirm this
    reading or amend.
-->

# Gaea Constitution

Gaea is a self-hosted Discord bot providing guild engagement, moderation, and automation
capabilities in the problem space occupied by Mee6. Gaea is a security product that happens to
deliver engagement features, not an engagement product with security bolted on. Every rule below
exists to keep that ordering intact.

## Core Principles

### I. Security-First by Default (NON-NEGOTIABLE)

Security constraints outrank feature scope, delivery schedule, and developer convenience. When a
requirement conflicts with a control in this section, the feature is cut or deferred — never the
control.

- All input originating outside the trust boundary — Discord gateway events, interaction payloads,
  HTTP request bodies, environment, configuration files, database rows written by a prior version —
  MUST be validated against an explicit schema at the boundary and rejected on failure. Parsed,
  typed values cross into the domain; raw strings MUST NOT.
- Discord HTTP interaction endpoints MUST verify the `X-Signature-Ed25519` /
  `X-Signature-Timestamp` pair against the application public key before any body parsing or side
  effect, and MUST return HTTP 401 on failure (Discord Developer Docs, *Receiving and Responding —
  Security and Authorization*; Ed25519 per RFC 8032).
- Gateway intents MUST be requested at the least privilege that satisfies a shipped feature.
  Privileged intents (`GUILD_MEMBERS`, `GUILD_PRESENCES`, `MESSAGE_CONTENT`) MUST each be justified
  in writing in the ADR for the feature that requires them (Discord Developer Docs, *Gateway
  Intents*).
- Secrets (bot token, client secret, signing keys, database credentials) MUST be injected at
  runtime from the environment or a secret manager. Committing a secret to version control is a
  release-blocking incident requiring token rotation via the Discord Developer Portal, not a
  `git revert`.
- All network egress MUST use TLS 1.3 where the peer supports it and MUST reject TLS below 1.2
  (RFC 8446; RFC 8996 deprecates TLS 1.0/1.1). Certificate validation MUST NOT be disabled in any
  build profile, including local development.
- Every command handler MUST perform an explicit authorization check against the invoking member's
  effective permissions and the guild's configured role policy before executing a privileged
  action. Absence of a check is a denial, never an allow: the default branch MUST deny.
- Any password or shared secret at rest MUST be hashed with Argon2id at parameters no weaker than
  the RFC 9106 §4 second recommended configuration (t=3, m=64 MiB, p=4). Tokens issued by Gaea
  MUST be generated from a CSPRNG with at least 128 bits of entropy.
- Untrusted content MUST be rendered inertly: user-controlled text echoed into Discord messages
  MUST have mentions suppressed via `allowed_mentions` rather than by string escaping, and any
  web surface MUST apply contextual output encoding plus a `default-src 'self'` Content Security
  Policy.
- Dependencies and first-party code MUST pass automated SAST and SCA in CI. A finding of CVSS v4.0
  base score >= 7.0 (FIRST CVSS v4.0 specification) blocks merge and blocks release.

*Rationale:* A Discord bot holds a token that grants read access to member data and write access to
every guild that installed it. Compromise is multi-tenant by construction, so the blast radius of a
single defect is every guild Gaea serves. Controls are stated as absolutes because a
case-by-case exception process is where security-first programs actually fail.

### II. Total Documentation (NON-NEGOTIABLE)

Undocumented code is incomplete code and MUST NOT be merged.

- Every exported/public item — module, type, function, method, constant, error variant — MUST carry
  a doc comment in the language's native documentation format, stating its purpose, the meaning of
  each parameter, the meaning of the return value, every error or panic condition, and any
  invariant the caller must uphold.
- Documentation coverage MUST be enforced mechanically, not by reviewer diligence: the build MUST
  fail on a missing doc comment for a public item (e.g. `#![deny(missing_docs)]` in Rust, an
  equivalent linter gate in any other selected language).
- Every non-obvious implementation choice MUST record *why*, not *what*. Comments restating the
  code are noise and MUST be removed in review.
- Every security control MUST name the threat it mitigates and cite the standard, RFC, or vendor
  documentation it derives from, inline at the control.
- Architecturally significant decisions — language, runtime, datastore, any privileged intent, any
  cryptographic primitive, any new third-party dependency — MUST be recorded as a numbered
  Architecture Decision Record in `docs/adr/` containing: context, options considered with
  measured or cited evidence, decision, and consequences.
- Every user-facing command MUST ship with its help text, required permissions, and rate-limit
  behavior documented in user-facing docs in the same change that introduces the command.

*Rationale:* Gaea is a self-hosted security product. Operators must be able to audit what the bot
does with their members' data without reading the source, and maintainers must be able to reconstruct
the threat model years later. Mechanical enforcement is required because documentation discipline
decays under delivery pressure in exactly the way review checklists do not catch.

### III. Selection by Engineering Merit, Not Popularity

Language, runtime, library, and datastore selections MUST be justified by measured performance,
demonstrated reliability, and maturity. Popularity, familiarity, GitHub stars, and community
sentiment are NOT admissible justifications.

- A candidate MUST be evaluated in an ADR against, at minimum: memory safety and the class of
  defects the language makes unrepresentable; throughput and tail latency under the project's
  workload shape (high-fanout gateway event processing and burst-heavy HTTP interaction responses);
  concurrency model and its failure behavior under backpressure; maintenance signal (release
  cadence, unresolved CVE count and mean time-to-patch, bus factor, governance model); license
  compatibility; and total transitive dependency count.
- Performance claims MUST be supported by a benchmark run on project-representative workloads or by
  a citation to a reproducible published benchmark. Vendor marketing numbers are inadmissible.
- Maturity requires a demonstrated track record: a documented security-reporting channel, a history
  of patched vulnerabilities, and evidence of API stability in practice. A stable (>= 1.0) release
  line is the preferred evidence of that track record, and where two candidates are otherwise of
  comparable engineering merit the one on a >= 1.0 line MUST be chosen.
- A pre-1.0 dependency MAY be adopted only when every one of the following holds, and the ADR
  records each: (a) no >= 1.0 alternative of comparable engineering merit exists; (b) the upstream
  repository is not archived or deprecated and shows commit activity within the last 90 days;
  (c) the license permits forking; (d) the dependency is isolated behind an internal boundary owned
  by this project, such that no type it defines appears in domain logic, and it can be replaced or
  forked without touching that logic; (e) a named maintainer on this project owns tracking it; and
  (f) the dependency's release cadence is measured and recorded, not assumed.
- Unmaintained packages MUST be rejected without exception. A package is unmaintained when its
  repository is archived, is explicitly deprecated by its authors, or has received no commit in
  twelve months. Infrequent releases are not by themselves disqualifying where development is
  demonstrably ongoing, but the gap MUST be recorded and the isolation requirement in (d) applies.
- If no option meeting these conditions exists, the capability is implemented in-house and the
  decision recorded.
- Every new direct dependency MUST justify its transitive cost. A dependency that supplies a
  function implementable in under roughly 50 auditable lines MUST be rejected — each package is
  additional supply-chain attack surface (NIST SP 800-218 SSDF, PW.4).
- Deprecated, sunsetted, or end-of-life technology MUST be rejected outright, including where it is
  the incumbent popular choice.

*Rationale:* Popularity correlates with the availability of tutorials, not with correctness under
load or with the absence of memory-safety defects. A security-first multi-tenant service is exactly
the workload where that divergence is expensive.

### IV. Current, Pinned, and Verified Dependencies

Gaea MUST run on the latest stable release of every language toolchain, module, and package it
depends on. That currency MUST be achieved through pinned, verified upgrades — never through
floating version resolution.

- Manifests MUST declare dependencies at exact versions and the resolved lockfile MUST be committed.
  Floating specifiers (`*`, `latest`, unbounded ranges) are prohibited: a build that is not
  byte-reproducible cannot be audited, and a resolver free to pull a new release is an
  unauthenticated remote code execution path into CI (cf. CVE-2024-3094, xz-utils).
- CI MUST fail when any pinned dependency is more than 30 days behind its latest stable release, and
  MUST fail immediately — with no grace period — when a pinned dependency has a known advisory.
  Currency is therefore enforced mechanically rather than left to intent.
- A newly published upstream release MUST age for 72 hours before adoption, except for a release
  that fixes an advisory affecting Gaea, which MUST be adopted immediately. The cooldown is the
  detection window for a compromised publish.
- Every dependency addition or upgrade MUST be verified against the upstream integrity hash or
  signature recorded in the lockfile. Unsigned or hash-mismatched artifacts MUST be rejected.
- Pre-release, release-candidate, nightly, and beta versions MUST NOT be used in any artifact
  that reaches production.
- A software bill of materials in SPDX or CycloneDX format MUST be generated for and published with
  every release (NIST SP 800-218 SSDF, PS.3.2).

*Rationale:* "Latest stable" and "reproducible" are not in tension once currency is treated as a CI
assertion over pinned values rather than as a resolver directive. The pinning is what makes the
currency auditable, and the cooldown is what keeps automatic currency from becoming an automatic
supply-chain compromise.

### V. Proven Correctness Before Merge

Correctness MUST be demonstrated by executable tests, not asserted in review.

- Tests MUST be written before the implementation for every bug fix and every security control. A
  regression test MUST fail against the unpatched code before the fix lands; a test that has never
  been observed to fail proves nothing.
- Every authorization check, input validator, and cryptographic boundary MUST have tests covering
  both the allow path and the deny path, including malformed, oversized, and adversarial input.
- Contract tests MUST cover every Discord API interaction, including the documented failure modes:
  HTTP 429 with `retry_after`, gateway resume and reconnect, and invalid-session handling.
- The build MUST fail on any compiler or linter warning. Warnings suppressed rather than fixed MUST
  carry an inline justification naming the reason.
- Merges to the mainline MUST be blocked while any test fails. Skipped, flaky-quarantined, or
  commented-out tests MUST be fixed or deleted, never accumulated.

*Rationale:* The deny path is the path that matters in an authorization system, and it is the path
that manual review reliably overlooks because the happy path is what gets exercised by hand.

### VI. Observability and Auditability

Gaea MUST be diagnosable in production without attaching a debugger and without reading member
content.

- All logging MUST be structured (machine-parseable key-value or JSON) and MUST carry a correlation
  identifier propagated across gateway event, command execution, and outbound API call.
- Logs MUST NOT contain secrets, tokens, authorization headers, or message content. Member and guild
  identifiers MAY be logged as opaque snowflakes; any other personal data MUST be redacted at the
  logging boundary, enforced by a type-level or serializer-level redaction mechanism rather than by
  developer discipline.
- Every privileged action — moderation action, configuration change, permission grant — MUST emit
  an immutable audit record capturing actor, target, action, timestamp, and outcome.
- The service MUST expose health and readiness endpoints and MUST export metrics for gateway
  connection state, event processing latency, command error rate, and Discord rate-limit
  consumption.
- Errors MUST be handled explicitly at every call site. Silently swallowed errors and unchecked
  failures are defects; the process MUST fail loudly and restart cleanly rather than continue in an
  indeterminate state.

*Rationale:* A multi-tenant bot's incident response depends on reconstructing what the bot did in a
guild the responder cannot see. Audit records and redaction-by-construction are what make that
possible without turning the log store into a secondary breach target.

## Security and Platform Constraints

**Discord platform compliance.** Gaea MUST comply with the Discord Developer Terms of Service and
Developer Policy. Rate limiting MUST be respected proactively: the client MUST honor per-route
bucket headers (`X-RateLimit-Bucket`, `-Remaining`, `-Reset-After`), MUST respect the global limit
of 50 requests per second per bot, and MUST never approach the 10,000-invalid-requests-per-10-minutes
threshold that triggers a Cloudflare ban (Discord Developer Docs, *Rate Limits*). A 429 response
MUST be treated as a defect in the client's own limiter, logged as such, and honored via
`retry_after` with jitter.

**Data minimization.** Gaea MUST collect and retain only the data required by an enabled feature.
Message content MUST NOT be persisted unless a specific feature requires it, in which case the
retention period, purpose, and deletion mechanism MUST be documented and configurable by the guild
operator. Data MUST be deleted on guild removal and on member removal.

**Privilege isolation.** The runtime process MUST execute as a non-root, unprivileged user in a
container with a read-only root filesystem, no capabilities beyond those explicitly required, and
`no-new-privileges` set (CIS Docker Benchmark). The database account used by the application MUST
hold only the DML privileges it requires; schema migration MUST use a separate, privileged account.

**Cryptographic agility.** Cryptographic primitives MUST be sourced from a maintained, audited
library. Hand-rolled cryptography is prohibited without exception. The primitive in use for each
purpose MUST be recorded in an ADR so it can be replaced when deprecated.

**Supply chain integrity.** Release artifacts MUST be built in CI from a tagged commit, MUST be
reproducible, and MUST carry build provenance attestation meeting SLSA v1.0 Build Level 2 or
higher. Artifacts built on a developer workstation MUST NOT be released.

## Development Workflow and Quality Gates

**Branching and review.** All changes reach the mainline through a pull request. Direct pushes to
the mainline are prohibited. Every pull request requires at least one approving review; changes
touching authentication, authorization, cryptography, or dependency manifests require review by a
second reviewer with explicit sign-off on the security impact.

**Merge gates.** The following MUST all pass before merge, enforced by CI rather than by convention:

1. Build succeeds with zero compiler and linter warnings.
2. Full test suite passes; no skipped or quarantined tests.
3. Documentation coverage gate passes for all public items (Principle II).
4. SAST finds no issue at CVSS v4.0 base >= 7.0 (Principle I).
5. SCA finds no advisory in the dependency graph, and no pinned dependency is >30 days stale
   (Principle IV).
6. Secret scanning finds no credential in the diff or in history.
7. An ADR accompanies any architecturally significant change (Principle II).

**Definition of done.** A change is done when: the code is merged, its tests pass in CI, its public
items are documented, its user-facing documentation is updated in the same change, its ADR (if
required) is committed, and its observability — logs, metrics, audit records — is in place. Partial
delivery MUST be reported as partial; "done except for tests" and "done except for docs" are not
states this project recognizes.

**Incident response.** A discovered vulnerability in Gaea or in a dependency MUST be triaged within
24 hours. Anything scoring CVSS v4.0 base >= 7.0 MUST have a patched release or a documented
mitigation within 72 hours of triage. Suspected bot-token compromise MUST trigger immediate token
rotation before any root-cause analysis begins.

## Governance

This constitution supersedes all other development practices, conventions, and preferences in this
repository. Where a tool default, a style guide, or a reviewer's preference conflicts with a rule
here, this document wins.

**Amendment procedure.** Amendments are proposed as a pull request modifying this file alone. The
proposal MUST state the rule being changed, the concrete problem motivating the change, and the
migration plan for any code that the current rule permits and the amended rule would forbid. An
amendment is adopted when approved by the project maintainer. Amendments take effect on merge and
are not retroactive: existing code that violates a newly added rule MUST be tracked to remediation,
not grandfathered indefinitely.

**Versioning policy.** This constitution is versioned per Semantic Versioning 2.0.0 (semver.org):

- MAJOR — a principle is removed, or redefined such that previously compliant code becomes
  non-compliant.
- MINOR — a principle or section is added, or existing guidance is materially expanded.
- PATCH — clarification, wording, or typo correction with no change in obligation.

**Compliance review.** Every pull request review MUST verify compliance with these principles;
reviewers approve the constitutional compliance of a change, not only its correctness. Any deviation
MUST be justified in the pull request description against the specific principle it departs from,
and MUST be approved explicitly — silence is not approval. Complexity introduced without a recorded
justification MUST be rejected. A full compliance audit of the codebase against this document MUST
be performed before each release and the result recorded in the release notes.

**Runtime guidance.** Day-to-day development guidance that elaborates but never contradicts this
constitution lives in `CLAUDE.md` at the repository root and in the ADR set under `docs/adr/`. Where
guidance and constitution disagree, the constitution governs and the guidance MUST be corrected.

**Version**: 1.1.0 | **Ratified**: 2026-09-15 | **Last Amended**: 2026-09-16
