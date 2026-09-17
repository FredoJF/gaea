# Feature Specification: Web Management Dashboard

**Feature Branch**: `002-web-management-dashboard`

**Created**: 2026-09-16

**Status**: Draft

**Input**: User description: "Mandatory feature : The bot must be linked to a web application, which allow the discord server owner, administrators or designed manager role to easily manage almost every feature of the bot."

**Relationship to other specs**: This specification resolves the configuration-surface question left
open in [001-guild-automation-suite](../001-guild-automation-suite/spec.md). The dashboard is the
management surface for the features defined there; that spec defines *what* is configurable, this
one defines *who* may configure it and *how* they reach it.

## Clarifications

### Session 2026-09-16

- Q: Will the dashboard be reachable from the public internet, or only from a private network you control? → A: Public internet. TLS certificates and the reverse proxy are the operator's deployment responsibility, not the application's. Authorized users sign in with their Discord account.
- Q: Must every bot setting also be configurable through in-Discord slash commands, or is the dashboard the only place configuration happens? → A: Dashboard-only for configuration, plus a small fixed command set — a per-feature emergency disable, and the temporary-voice-channel owner controls that must live in Discord by nature.
- Q: When a server owner designates a role as a bot manager, does that role get to manage every feature, or can it be limited to specific features? → A: Two tiers, not per-feature. A designated manager role manages every feature; a separate designated viewer role can see settings and the activity record but change nothing. Per-feature grants are deliberately deferred past V1 to keep the authorization model to a single comparison per request.
- Q: Does the dashboard need to be available in more than one language for V1? → A: English only for V1, but built so a language can be added later without restructuring — user-visible text kept separate from code, locale-aware dates, times and numbers from the start.
- Q: How long should the activity record be kept before it is deleted? → A: 90 days by default, operator-configurable. Long enough to explain a problem noticed weeks later, short enough to bound storage growth and breach exposure, and consistent with the window Discord keeps for its own audit log.

## User Scenarios & Testing *(mandatory)*

Actors referenced throughout:

- **Server owner** — the single Discord account that owns a guild.
- **Administrator** — a guild member whose Discord permissions include guild administration.
- **Manager** — a guild member holding a role the owner or an administrator has designated as
  authorized to manage the bot, without that member holding Discord administrative permissions. A
  manager manages every feature; management authority is not divisible per feature in this version.
- **Viewer** — a guild member holding a role the owner or an administrator has designated as
  authorized to observe the bot. A viewer can see every setting and the activity record and can
  change nothing at all.
- **Visitor** — any authenticated account with no authority over a given guild. A visitor is
  indistinguishable from an attacker for the purposes of this specification.

### User Story 1 - Sign in and reach the right servers (Priority: P1)

An owner or administrator opens the dashboard, signs in with their Discord account, and sees exactly
the servers they are entitled to manage: those where they hold authority and where the bot is
already present. Servers where they hold authority but the bot is absent are shown separately with a
way to add it. Servers where they hold no authority are not shown at all.

**Why this priority**: Nothing else in the dashboard can exist without it, and it is where the
entire security posture of the feature is decided. Every subsequent story inherits the identity,
session, and authorization model this story establishes.

**Independent Test**: Sign in with an account that owns one server, administers a second, is a plain
member of a third, and has no relationship to a fourth. Confirm the first two appear, the third and
fourth do not, and that no navigation or direct address reaches the third or fourth.

**Acceptance Scenarios**:

1. **Given** an unauthenticated visitor, **When** they open any management page, **Then** they are
   sent to sign in and no guild data is disclosed beforehand.
2. **Given** a signed-in user, **When** their server list is displayed, **Then** it contains every
   server where they are owner, administrator, or designated manager and the bot is present, and no
   other server.
3. **Given** a signed-in user with authority over a server the bot has not joined, **When** the list
   is displayed, **Then** that server appears in a distinct "add the bot" state and exposes no
   configuration controls.
4. **Given** a signed-in user, **When** they address a management page for a server they hold no
   authority over — by editing the address directly or replaying a link — **Then** access is refused
   identically to a non-existent server, and the attempt is recorded.
5. **Given** a user who was an administrator when they signed in, **When** their permission is
   revoked in Discord, **Then** their access to that server's management pages ends within 5 minutes
   without requiring them to sign out.
6. **Given** a user who has signed out, **When** they replay a previously captured session, **Then**
   access is refused.
7. **Given** a signed-in user, **When** their session has been idle beyond the inactivity limit or
   has exceeded its absolute lifetime, **Then** it is terminated and re-authentication is required.

---

### User Story 2 - Manage every bot feature from the browser (Priority: P1)

An authorized user selects a server and configures any of the bot's features — greetings, scheduled
messages, temporary voice channels, Twitch alerts, YouTube alerts — through forms that show the
server's real channels, roles, and categories as choices rather than requiring identifiers to be
typed. Changes take effect on the running bot without a restart, and the user can see the effect of a
message template before saving it.

**Why this priority**: This is the feature as stated. It shares P1 with Story 1 because a dashboard
that authenticates but cannot configure anything delivers nothing; the two together are the minimum
shippable unit.

**Independent Test**: For each feature in [001](../001-guild-automation-suite/spec.md), configure it
entirely through the dashboard in a test server and verify the bot's behavior changes accordingly,
without using any in-Discord command.

**Acceptance Scenarios**:

1. **Given** an authorized user on a server's management page, **When** they change any feature
   setting and save, **Then** the change is persisted and the running bot honors it within 30
   seconds with no restart.
2. **Given** a user editing a setting that references a channel, role, or category, **When** the
   form is displayed, **Then** it offers the server's actual channels, roles, and categories as
   selectable choices, and excludes any the bot cannot act on.
3. **Given** a user editing a message template, **When** they request a preview, **Then** the
   rendered result is displayed with sample values before any save occurs.
4. **Given** a user submits a setting that is invalid — an unknown placeholder, a length beyond the
   platform limit, a channel the bot cannot post in — **When** they save, **Then** the save is
   rejected with a message identifying the specific field and reason, and no partial change is
   persisted.
5. **Given** two authorized users editing the same server's settings simultaneously, **When** the
   second saves over the first's change, **Then** the conflict is detected and the second user is
   told rather than silently overwriting.
6. **Given** a user changes a setting, **When** the change is saved, **Then** an audit entry records
   who changed what, from which value to which value, and when.
7. **Given** a user attempts an action that would cause the bot to notify every member of the
   server, **When** they save, **Then** the action requires an explicit, separate confirmation and
   is refused outright if the acting user lacks the corresponding authority in Discord.
8. **Given** a feature has been deliberately excluded from the dashboard, **When** the user browses
   the management pages, **Then** the exclusion and its reason are stated rather than the feature
   being silently absent.

---

### User Story 3 - Delegate management without granting Discord admin (Priority: P2)

A server owner designates one or more existing Discord roles as bot managers, and optionally other
roles as viewers. Members holding a manager role can manage every feature of the bot through the
dashboard without being granted Discord administrative permissions. Members holding a viewer role
can see every setting and the activity record but can change nothing — enough to diagnose a problem
and report it, not enough to cause one. The owner can withdraw either designation at any time, and
withdrawal takes effect promptly.

**Why this priority**: This is the reason the description names a "designated manager role"
separately from owner and administrator — it exists so that community moderators can run the bot
without being handed the keys to the server. It is P2 rather than P1 only because owners and
administrators can operate the dashboard without it.

**Independent Test**: Designate a role, confirm a member holding it can manage the bot and cannot
reach anything else, then withdraw the designation and confirm access ends.

**Acceptance Scenarios**:

1. **Given** an owner or administrator on the access settings page, **When** they designate a role
   as manager, **Then** members holding that role gain management access within 5 minutes.
2. **Given** a designated manager, **When** they open the dashboard, **Then** they can manage the
   bot's features for that server and cannot alter which roles are designated as managers.
3. **Given** a designated manager, **When** they attempt to escalate their own access — designating
   an additional role, removing the bot, or altering the audit record — **Then** the attempt is
   refused and recorded.
4. **Given** a designation is withdrawn, **When** an affected member next acts, **Then** their
   management access is gone within 5 minutes, including for a session established beforehand.
5. **Given** a member loses the designated role in Discord, **When** they next act, **Then** their
   management access ends within 5 minutes.
6. **Given** a designated role is deleted in Discord, **When** the access settings are next viewed,
   **Then** the stale designation is shown as invalid and grants no access.
7. **Given** a designated viewer, **When** they open a server's management pages, **Then** every
   setting and the activity record are legible to them and every control that would change something
   is absent or inert.
8. **Given** a designated viewer, **When** they submit a change by any means — a crafted request, a
   replayed form, a command — **Then** it is refused and the attempt is recorded.
9. **Given** a member holds both a manager role and a viewer role, **When** their authority is
   established, **Then** the higher of the two applies.

---

### User Story 4 - See what the bot did and why (Priority: P3)

An authorized user reviews a server-scoped activity record: configuration changes with their author,
automated messages the bot sent, and actions the bot could not perform, each with the reason. When a
feature is not working, the user can determine why without contacting the operator.

**Why this priority**: It converts every silent failure in
[001](../001-guild-automation-suite/spec.md) — missing permission, deleted channel, exhausted quota,
suspended schedule — into something the person responsible can actually see and fix. It is the
difference between a bot that appears broken and a bot that explains itself.

**Independent Test**: Deliberately break a configuration (remove the bot's permission to post in the
greeting channel), trigger the feature, and confirm the dashboard states the cause in plain language.

**Acceptance Scenarios**:

1. **Given** configuration changes have occurred, **When** a user views the activity record, **Then**
   each entry shows actor, action, target, timestamp, and outcome.
2. **Given** an automated action failed, **When** the user views the activity record, **Then** the
   entry states the cause in language an operator can act on, not an internal error code.
3. **Given** a user views the activity record, **When** entries are displayed, **Then** they are
   scoped to that server alone and disclose nothing about any other server.
4. **Given** a user views the activity record, **When** entries are displayed, **Then** no secret,
   credential, or session identifier appears in any entry.
5. **Given** a feature is currently suspended due to repeated failure, **When** the user views its
   settings, **Then** the suspension and its cause are stated on that feature's own page, not only
   in the activity record.

---

### User Story 5 - Get a new server running quickly (Priority: P3)

A user who has never used the bot adds it to their server from the dashboard, is returned to the
dashboard afterwards, and is guided through enabling their first feature. The dashboard tells them
what the bot still needs — a missing permission, a missing platform authorization — rather than
failing silently later.

**Why this priority**: Directly serves the "easily manage" requirement. It is ranked below the
stories that establish capability because it improves the path to value rather than creating the
value.

**Independent Test**: Starting from a server with no bot, complete the add-and-configure path
entirely from the dashboard and reach a working greeting.

**Acceptance Scenarios**:

1. **Given** a user with authority over a server the bot has not joined, **When** they choose to add
   the bot, **Then** they are taken through the platform's authorization flow and returned to that
   server's management page.
2. **Given** the bot has just joined, **When** the management page loads, **Then** any missing
   permission required by an available feature is named explicitly with what it enables.
3. **Given** a feature depends on an authorization the operator has not supplied, **When** the user
   views it, **Then** it is shown as unavailable with the reason, rather than appearing configurable
   and then failing.
4. **Given** a first-time user, **When** they follow the guided path, **Then** they reach a working
   configured feature without leaving the dashboard.

---

### Edge Cases

**Authorization and session integrity**

- A user's Discord permissions change — promotion, demotion, role deletion, ownership transfer —
  while they hold an active dashboard session.
- A user is banned or leaves a server while holding an active session scoped to it.
- The bot is removed from a server while an authorized user is editing its settings.
- A session identifier is captured and replayed from a different client or network.
- A user is induced to submit a state-changing request from a third-party site.
- A user signs in from multiple devices and signs out on one of them.
- The upstream identity provider is unreachable, so authority cannot be verified at all.
- A user holds authority over hundreds of servers, making authority verification expensive.

**Data integrity and concurrency**

- Two authorized users edit the same setting simultaneously.
- A setting is changed through the dashboard at the same moment it is changed in Discord.
- A referenced channel, role, or category is deleted between the form being rendered and submitted.
- A form is submitted twice — by a double click, a retry, or a replayed request.
- A submission references a channel or role belonging to a different server than the one in scope.

**Abuse and availability**

- A user submits settings repeatedly at machine speed to exhaust the service.
- A user configures content intended to trigger a mass notification of the server.
- A user pastes content designed to be interpreted as markup or a formula when displayed to another
  user or exported.
- Many users sign in simultaneously, each requiring their authority to be established.
- The dashboard is unreachable while the bot continues running, and vice versa.
- A feature misbehaves in a server while the dashboard is unavailable, so the only remedy is the
  in-Discord disable command.
- A feature is disabled by command during an incident and nobody remembers why when it is later
  found switched off.
- A client forges a forwarding header to evade rate limiting or to write a false origin into the
  audit record.
- The application is deployed without the upstream proxy the operator intended, exposing it
  directly, or is deployed behind a proxy it has not been told to trust.
- Unauthenticated internet traffic — scanners, crawlers, credential-stuffing attempts — arrives
  continuously against the sign-in path.

**Presentation**

- A server has hundreds of channels or roles, making selection lists unusable without search.
- Names of servers, channels, roles, and members contain scripts, emoji, right-to-left text, or
  characters that alter the meaning of surrounding text when rendered.
- A user operates the dashboard on a small screen, by keyboard only, or with a screen reader.

## Requirements *(mandatory)*

### Functional Requirements

**Identity and session**

- **FR-001**: System MUST authenticate users through their Discord account and MUST NOT ask users
  for a password or store one.
- **FR-002**: System MUST establish a session bound to the authenticated account, and MUST terminate
  it on sign-out, after a period of inactivity, and at an absolute maximum age, whichever comes
  first.
- **FR-003**: System MUST invalidate a session on the server side at sign-out such that a replayed
  session identifier grants no access.
- **FR-004**: System MUST reject any state-changing request that does not demonstrably originate
  from the dashboard itself.
- **FR-005**: System MUST NOT expose the bot's credentials, platform secrets, or any other server's
  data to any authenticated user under any circumstances.
- **FR-006**: System MUST record every authentication, sign-out, and refused access attempt with the
  account, the server in scope, and the outcome.

**Authorization**

- **FR-007**: System MUST grant management access to a server only to its owner, to members holding
  Discord administrative permission for it, and to members holding a role designated as manager for
  it, and MUST deny everyone else.
- **FR-008**: System MUST re-establish a user's authority over a server from the authoritative
  source at least every 5 minutes, and MUST end access within that window when authority is lost.
  Cached authority MUST never outlive that window.
- **FR-009**: System MUST verify authority for the specific server in scope on every request that
  reads or changes that server's settings, and MUST NOT rely on the user having reached the page
  through the interface.
- **FR-010**: System MUST make a refusal to access a server the user has no authority over
  indistinguishable from that server not existing, so that the interface does not disclose which
  servers exist.
- **FR-041a**: FR-041's "sole configuration surface" governs the surfaces guild owners,
  administrators, managers and viewers reach — Discord and the web. It does not govern the host
  operator, who holds shell access and the database credential and therefore already has
  unconditional authority over every setting. Operator-side tooling is not a second user-facing
  configuration path and creates no additional authorization surface to keep correct.

- **FR-011**: Only owners and administrators MUST be able to designate or withdraw manager and
  viewer roles; designated managers and viewers MUST NOT be able to alter the set of designated
  roles or otherwise widen their own access.
- **FR-011a**: System MUST recognise exactly two delegated levels — manager, who may change every
  setting, and viewer, who may read every setting and the activity record and change nothing.
  Management authority MUST NOT be divisible per feature in this version; a request therefore
  resolves to a single authority level, not to a set of per-feature grants.
- **FR-011b**: System MUST resolve a member holding several designated roles to the highest
  authority those roles confer.
- **FR-011c**: System MUST enforce the viewer restriction on the server side for every request, and
  MUST NOT rely on controls being hidden in the interface.
- **FR-012**: System MUST refuse any dashboard action whose effect in Discord the acting user would
  not be permitted to perform themselves, so that the bot cannot be used to exceed the user's own
  authority.
- **FR-013**: System MUST require an explicit, separate confirmation for any action that would
  notify every member of a server or that would remove configuration irrecoverably.

**Feature management**

- **FR-014**: System MUST allow every setting of every feature defined in
  [001](../001-guild-automation-suite/spec.md) to be viewed and changed from the dashboard, with the
  sole exceptions listed in FR-015.
- **FR-015**: System MUST exclude from the dashboard, and MUST state as excluded: the bot's own
  credentials and platform authorizations, deployment and hosting settings, service-wide rate
  ceilings, and any setting whose misuse would affect servers other than the one in scope. These
  remain the self-hosting operator's responsibility. This exclusion set defines the boundary of
  "almost every feature".
- **FR-016**: System MUST present channels, roles, categories, and other server objects as
  selections drawn from the live server rather than requiring identifiers to be entered.
- **FR-017**: System MUST exclude from those selections any object the bot cannot act upon, and MUST
  state why when a user's expected choice is absent.
- **FR-018**: System MUST apply a saved change to the running bot within 30 seconds without
  requiring a restart.
- **FR-019**: System MUST validate every submitted setting against the same rules the bot enforces,
  and MUST reject an invalid submission in full — naming the offending field and reason — rather
  than persisting it partially.
- **FR-020**: System MUST render a preview of any message template on request, visible only to the
  requesting user, before the template is saved.
- **FR-021**: System MUST detect a concurrent modification of the same settings and MUST inform the
  later user rather than silently discarding the earlier change.
- **FR-022**: System MUST treat a repeated identical submission as a single change.
- **FR-023**: System MUST reject a submission referencing an object belonging to a server other than
  the one in scope.

**Visibility and accountability**

- **FR-024**: System MUST present a server-scoped activity record showing configuration changes with
  their author and automated actions with their outcome.
- **FR-025**: System MUST state the cause of any failed or suspended automated action in language an
  operator can act upon, on the affected feature's own page as well as in the activity record.
- **FR-026**: System MUST exclude secrets, credentials, session identifiers, and member message
  content from everything it displays or exports.
- **FR-027**: System MUST record every configuration change with actor, server, setting, previous
  value, new value, and timestamp, and MUST make that record unalterable from the dashboard.
- **FR-049**: System MUST delete activity record entries once they reach the configured retention
  age, defaulting to 90 days, and MUST apply that deletion automatically without operator
  intervention. Retention MUST be operator-configurable so that a self-hoster subject to different
  obligations can change it without a code change.
- **FR-050**: System MUST state the effective retention period wherever the activity record is
  displayed, so that a user does not mistake deleted history for history that never existed.
- **FR-051**: System MUST delete a server's activity record when the bot is removed from that
  server, on the same schedule as that server's configuration
  (FR-009 of [001](../001-guild-automation-suite/spec.md)), regardless of the retention age of
  individual entries.

**Safety of displayed content**

- **FR-028**: System MUST render all server-derived and user-supplied text — server names, channel
  names, role names, member names, templates — inertly, such that no such text can be interpreted as
  instructions by the viewing browser or by any application the data is exported to.
- **FR-029**: System MUST limit the rate at which any account can submit changes and the rate at
  which any client can attempt authentication, and MUST record when a limit is reached.
- **FR-030**: System MUST remain available to other servers when any one server's configuration,
  authority lookup, or external dependency fails.

**Licence compliance**

- **FR-055**: System MUST offer every remote user interacting with the dashboard an opportunity to
  receive its Corresponding Source, through a prominent, discoverable link available without signing
  in. Gaea is licensed AGPL-3.0, whose §13 makes this an obligation of operating the software over a
  network, not an optional courtesy. An operator running a modified build MUST be able to point that
  link at their own source without modifying the application.
- **FR-056**: System MUST state the running version and, where the build provides it, the source
  revision, so that the source a user is offered is identifiable as the source actually running.

**External platform callbacks**

- **FR-052**: System MUST expose the Twitch and YouTube callback endpoints defined in
  [001](../001-guild-automation-suite/spec.md), verify each platform's signature before parsing the
  body or taking any action, and rate-limit them independently of dashboard traffic so that callback
  volume cannot degrade the dashboard or the reverse.
- **FR-053**: System MUST acknowledge a platform callback within that platform's deadline and hand
  the work off for separate processing. It MUST NOT perform announcement work before acknowledging:
  Twitch revokes subscriptions whose delivery failure rate is too high, so a handler coupled to
  Discord's latency can cause the application to be unsubscribed from every streamer at once.
- **FR-054**: System MUST surface upstream subscription faults — a Twitch revocation, a lapsed
  YouTube lease, a failed renewal — on the affected feature's page with the platform's stated
  reason, so that alerts silently stopping is a visible fault rather than a mystery.

**Public exposure**

- **FR-037**: System MUST derive the originating client address used for rate limiting (FR-029) and
  for the audit record (FR-006) from a configured, trusted set of upstream proxy addresses, and MUST
  ignore any client-supplied forwarding header arriving from an untrusted source. Without this,
  every request behind a proxy appears to originate from the proxy itself, which makes FR-029 either
  inert or a self-inflicted denial of service, and lets any client forge its identity in the audit
  record.
- **FR-038**: System MUST refuse to issue or accept a session over an unencrypted connection, and
  MUST be configurable to recognise that encryption terminates at an upstream proxy rather than at
  the application.
- **FR-039**: System MUST NOT acquire, renew, or manage TLS certificates and MUST NOT configure
  network ingress. These are the operator's deployment responsibility. The application MUST document
  what it requires of that deployment, including the trusted-proxy configuration FR-037 depends on,
  and MUST fail to start with an explanatory error rather than run insecurely when that
  configuration is absent or contradictory.
- **FR-040**: System MUST withstand unauthenticated traffic from arbitrary internet clients without
  degrading service for authenticated users, and MUST NOT disclose whether a given account, server,
  or resource exists to an unauthenticated caller.

**Language and formatting**

- **FR-045**: System MUST present its interface in English for this version. A language-selection
  mechanism is out of scope.
- **FR-046**: System MUST hold every user-visible string — interface text, validation messages,
  failure explanations, and the bot's default message templates — separately from the logic that
  uses it, such that adding a language requires supplying translations and no change to behavior.
- **FR-047**: System MUST format dates, times, and numbers according to an explicit locale rather
  than an ambient default, and MUST qualify every displayed time with its timezone (consistent with
  FR-029 of [001](../001-guild-automation-suite/spec.md)).
- **FR-048**: System MUST render text correctly regardless of script or writing direction, including
  server, channel, role, and member names containing right-to-left text, combining marks, or emoji,
  without that text altering the meaning or layout of surrounding content.

**Access and presentation**

- **FR-031**: System MUST be operable by keyboard alone and MUST be usable with assistive
  technology, meeting the accessibility standard named in the Assumptions section.
- **FR-032**: System MUST be usable on a phone-sized screen for every management task.
- **FR-033**: System MUST provide search or filtering wherever a server may present more items than
  fit on screen, including channels, roles, scheduled messages, and subscriptions.
- **FR-034**: System MUST show a signed-in user which servers they can manage, which require the bot
  to be added, and nothing else.

**Continuity between surfaces**

- **FR-035**: A change made through any surface MUST be visible through every other surface within
  30 seconds, with no surface holding a private copy of a setting.
- **FR-036**: System MUST attribute a change to the acting person regardless of which surface was
  used to make it.
- **FR-041**: The dashboard MUST be the only surface through which the bot is configured. In-Discord
  commands MUST be limited to the two exceptions in FR-042 and FR-043, so that every configuration
  path is authorized, validated, and tested exactly once.
- **FR-042**: System MUST provide, in Discord, a command that disables a named feature for the
  server, available to owners, administrators, and designated managers, and MUST apply it within 30
  seconds without requiring the dashboard to be reachable. It MUST disable only; it MUST NOT be able
  to enable a feature or alter any setting, so that the dashboard remains the sole path by which the
  bot's behavior can be widened.
- **FR-043**: System MUST provide, in Discord, the temporary-voice-channel owner controls defined in
  [001](../001-guild-automation-suite/spec.md) — renaming, participant limit, access restriction —
  to the owner of a live channel, because these act on a channel the member is occupying at that
  moment and a browser round-trip would make them unusable.
- **FR-044**: System MUST record a command-issued disable in the same audit record as a dashboard
  change, and MUST show on the affected feature's dashboard page that it was disabled, by whom, and
  when, so that a disable performed during an incident is not mistaken later for a configuration
  error.

### Key Entities *(include if feature involves data)*

- **Account**: An authenticated Discord identity. Holds no password. Retains only what is needed to
  identify the person and to re-establish their authority — no profile data beyond that.
- **Session**: A bound, expiring grant of access to an Account, with an issue time, a last-activity
  time, an absolute expiry, and a server-side revocation state. Terminated on sign-out, expiry, or
  revocation.
- **Authority Assessment**: A short-lived, cached determination that a given Account holds a given
  level of authority (owner, administrator, manager, viewer, none) over a given server. Bounded by FR-008;
  never trusted past its window.
- **Role Designation**: A per-server record naming a Discord role and the level it confers — manager
  or viewer. Created and removed only by an owner or administrator. Becomes invalid if the role
  ceases to exist. A server may hold several designations; a member resolves to the highest level
  any of their roles confers.
- **Configuration Change Record**: An immutable entry capturing actor, server, setting, previous
  value, new value, surface used, and timestamp. Feeds the activity record and satisfies the
  project's audit obligation.
- **Feature Status**: The current health of one feature on one server — enabled, disabled,
  misconfigured, or suspended — together with the human-readable cause when it is not healthy.
  Derived, not authored.
- **Server Summary**: The dashboard's view of a Discord server — its name, its icon, whether the bot
  is present, and the viewer's authority over it. Derived from the live platform, cached only within
  the FR-008 window.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A first-time user can sign in, add the bot to a server, and reach a working configured
  feature in under 5 minutes without reading documentation.
- **SC-002**: An experienced user can change any single setting in under 30 seconds from opening the
  dashboard.
- **SC-003**: 100% of the settings defined in [001](../001-guild-automation-suite/spec.md) are
  manageable from the dashboard, except those enumerated in FR-015, verified by inventory audit.
- **SC-004**: Zero instances, under adversarial testing, of any account reading or changing the
  settings of a server it holds no authority over — including by direct address, link replay, or
  request forgery.
- **SC-005**: 100% of authority revocations take effect within 5 minutes, verified by revoking
  permission during an active session.
- **SC-006**: Zero secrets, credentials, or member message content appear in any dashboard view,
  export, or activity record, verified by inspection of every surface.
- **SC-007**: 95% of page views render usable content within 2 seconds on a typical residential
  connection.
- **SC-008**: 99% of saved changes are reflected in the bot's behavior within 30 seconds.
- **SC-009**: The dashboard remains responsive with 20 concurrent authorized users and for an
  account holding authority over 50 servers — this version's target, matching the small deployment
  described in [001](../001-guild-automation-suite/spec.md). The design does not foreclose growth,
  but no claim is made or tested beyond it.
- **SC-010**: Every management task is completable by keyboard alone and on a 375-pixel-wide screen,
  verified by walkthrough of each task.
- **SC-011**: Zero unintended mass notifications originate from a dashboard action, verified by
  adversarial testing of every template and announcement path.
- **SC-012**: 90% of users encountering a misconfiguration identify its cause from the dashboard
  alone, without contacting the operator.
- **SC-013**: 100% of configuration changes are attributable to an actor and a timestamp in the
  immutable record.
- **SC-014**: The bot continues operating all configured features normally while the dashboard is
  entirely unavailable, verified by fault injection.
- **SC-015**: Rate limits apply per originating client rather than per proxy, verified by driving
  traffic through an upstream proxy from multiple distinct client addresses and confirming that one
  abusive client cannot limit another.
- **SC-016**: Sustained unauthenticated traffic against the sign-in path does not degrade response
  times for authenticated users beyond the SC-007 threshold, verified by load injection.
- **SC-017**: An authorized user can disable any misbehaving feature from within Discord in under 15
  seconds while the dashboard is entirely unavailable, verified by disabling the dashboard and
  timing the action.
- **SC-018**: 100% of the bot's settings are reachable from the dashboard and from nowhere else,
  except the two exceptions named in FR-042 and FR-043, verified by inventory audit.
- **SC-019**: Zero instances, under adversarial testing, of a designated viewer causing any change
  to any setting by any means, including crafted requests that bypass the interface.
- **SC-020**: 100% of user-visible strings are supplied from outside the logic that uses them,
  verified by audit; adding a second language requires no behavioral change.
- **SC-021**: Every displayed date and time carries an explicit timezone, and no displayed value
  depends on the viewing device's ambient locale, verified by walkthrough under two locale settings.
- **SC-022**: Activity record entries older than the configured retention age are absent from every
  view and export, and the stored record does not grow without bound, verified over a soak period
  that exceeds the retention age.
- **SC-023**: Removing the bot from a server leaves no trace of that server's activity record within
  the documented deletion window, verified by inspection after removal.
- **SC-024**: A remote user who has not signed in can reach an offer of the Corresponding Source and
  identify the running version from the dashboard alone, verified by walkthrough — the obligation
  AGPL-3.0 §13 places on operating this software over a network.
- **SC-025**: An upstream alert subscription fault — a Twitch revocation or a lapsed YouTube lease —
  is visible on the affected feature's page with its stated cause within one reconciliation
  interval, verified by inducing both.

## Assumptions

**Scope boundaries**

- The dashboard manages the features defined in
  [001-guild-automation-suite](../001-guild-automation-suite/spec.md). It introduces no bot feature
  of its own; its value is entirely in managing, observing, and delegating.
- "Almost every feature" is bounded by FR-015. Everything else is in scope.
- Gaea is licensed AGPL-3.0. Because the dashboard is a network-facing interface to the program,
  §13 obliges it to offer its Corresponding Source to remote users. This is a functional requirement
  of the product (FR-055, FR-056), not a packaging detail, and it is why an unauthenticated,
  discoverable route exists at all on a dashboard that otherwise reveals nothing before sign-in.
- The dashboard serves guild management only. It is not a public marketing site, a billing system, a
  premium-tier gate, or a support portal — all of which comparable products bundle and all of which
  are out of scope.
- Member-facing self-service — a member checking their own standing — is out of scope. Every user of
  the dashboard is acting on behalf of a server.
- The dashboard is a management surface, not a control channel: it MUST NOT be able to make the bot
  send arbitrary immediate messages outside the scheduled-message feature's own rules, because that
  would turn a dashboard session into a mass-notification capability.
- Configuration is not duplicated across surfaces. Building the same setting twice is how two
  authorization checks drift apart, and the resulting disagreement is silent. The two in-Discord
  exceptions are deliberately shaped so they cannot drift: one only disables, the other touches no
  stored configuration at all.

**Reasonable defaults adopted where the description was silent**

- Authentication is delegated to Discord rather than implemented locally. The application never
  handles a password, which removes credential storage, password reset, and credential stuffing from
  the threat model entirely.
- Authority is derived live from Discord rather than mirrored into the application, so that Discord
  remains the single source of truth and no separate permission model can drift out of sync.
- Authority caching is bounded at 5 minutes. An unbounded cache is the characteristic security
  defect of dashboards of this kind: a demoted administrator retains access until their session
  expires. A bound trades a small amount of upstream traffic for a bounded revocation window.
- Sessions expire after inactivity and at an absolute maximum age. Both are operator-configurable;
  defaults are conservative.
- Accessibility target is WCAG 2.2 Level AA (W3C Recommendation, October 2023).
- The interface is English-only in this version, but is built translation-ready (FR-046, FR-047).
  The translation work is deferrable; the structure that makes it possible is not, because
  retrofitting it means revisiting every screen and every default message template. Building it in
  from the start costs very little while the code is being written for the first time.
- The activity record is retained for 90 days by default and is operator-configurable (FR-049). The
  record names Discord members and is therefore personal data; GDPR Art. 5(1)(e) requires it be kept
  no longer than necessary for its stated purpose, which is letting a server owner reconstruct what
  the bot did. Unbounded retention would be both a continuously growing storage cost and a
  continuously growing breach liability. 90 days matches the window Discord keeps for its own guild
  audit log, so an operator correlating the two sees the same horizon on both sides.
- The dashboard and the bot share one audit record rather than keeping separate ones, so a
  configuration change and the automated delivery it caused appear on the same timeline.
- The dashboard and the bot share one configuration store and one audit record. Neither holds a
  private copy of a setting, which is what makes FR-035 achievable rather than aspirational.

**Dependencies**

- Requires the features of [001](../001-guild-automation-suite/spec.md) to exist in order to have
  anything to manage. Story 1 (sign in and list servers) is independently deliverable and testable
  before any of them.
- Requires the Discord platform for both identity and authority. When Discord is unreachable, the
  dashboard cannot establish authority and MUST refuse access rather than fall back to cached
  authority beyond its window.
- Requires the bot and the dashboard to be deployable and operable independently: an outage of one
  MUST NOT take down the other (SC-014).
- Requires the operator to terminate TLS and to place the application behind a reverse proxy in
  production, and to declare that proxy trusted in the application's configuration. The application
  supplies neither; it validates that it has been told about them (FR-037, FR-039).

**Open decisions**

- **RESOLVED (2026-09-16)**: In-Discord command parity — the dashboard is the sole configuration
  surface (FR-041). In-Discord commands are limited to a per-feature emergency disable (FR-042) and
  the temporary-voice-channel owner controls (FR-043). The disable command can only narrow the bot's
  behavior, never widen it, so an attacker who compromises a Discord account cannot use it to turn
  a feature on or change what it does.
- **RESOLVED (2026-09-16)**: Manager permission granularity — two tiers, manager and viewer, not
  per-feature grants (FR-011a). A manager manages everything; a viewer reads everything and changes
  nothing. This keeps authorization to a single comparison per request, which is the property that
  makes it testable; per-feature grants would turn one check into one check per feature, each able
  to be wrong independently. Per-feature granularity is deferred, not rejected — if it is added
  later, the level recorded on a Role Designation is the field that gains structure.
- **RESOLVED (2026-09-16)**: Deployment exposure — the dashboard is reachable from the public
  internet. The application's threat model therefore assumes continuous hostile, unauthenticated
  traffic (FR-040, SC-016). TLS certificate acquisition and renewal, and reverse proxy
  configuration, are the operator's deployment responsibility and explicitly outside the
  application (FR-039); the application's obligation is to state what it requires of that deployment
  and to refuse to start rather than run insecurely without it.
