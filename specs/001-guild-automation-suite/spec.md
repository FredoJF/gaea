# Feature Specification: Guild Automation Suite (v1)

**Feature Branch**: `001-guild-automation-suite`

**Created**: 2026-09-16

**Status**: Draft

**Input**: User description: "The discord bot must have the following features for the first version : - Custom welcome message in a specified channel when new users join the discord server. - Reminders ; message to automatically send in specified channels at a specific time - Temporary voice channels - Twitch alert when a specified streamer starts his live - Youtube alerts when a new video is posted in a specified channel"

## Clarifications

### Session 2026-09-16

- Q: How does a member get a temporary voice channel — by joining a designated "hub" voice channel that creates one for them, or by typing a command? → A: By joining a designated hub voice channel. The bot creates a channel and moves the member into it; no command is involved.
- Q: Should scheduled messages be able to repeat — daily, weekly — or only fire once at a single future moment? And whose clock decides what "9am" means? → A: One-time plus daily and weekly repeats, interpreted in a per-guild timezone. Daylight-saving transitions are handled by explicit rules: a local time that does not exist fires once at the next existing instant, and a local time that occurs twice fires once, on its first occurrence.
- Q: How many Twitch streamers and YouTube channels should a single Discord server be allowed to subscribe to? → A: 25 of each per guild by default, operator-configurable. The ceiling exists because total subscriptions across all guilds divided by the platforms' request budgets is what determines achievable alert latency.
- Q: When the bot is removed from a server, how long should that server's settings be kept before they are permanently deleted? → A: A 30-day grace period, then permanent deletion. Re-adding the bot within 30 days restores the configuration intact; after 30 days it is irrecoverable.
- Q: Should welcome messages be plain text, or should operators be able to build a richer card? → A: Plain text, plus an optional fixed-layout card carrying a colour and the joining member's avatar. Operator-supplied image URLs are excluded, so the bot never fetches remote content chosen by a guild.

## User Scenarios & Testing *(mandatory)*

Each user story below is an independently shippable slice. Implementing any single story yields a
bot that delivers standalone value to a guild operator; the stories share only the configuration
and permission substrate described in the cross-cutting requirements.

### User Story 1 - Greet new members automatically (Priority: P1)

A guild operator configures a welcome message and designates a channel for it. When a new member
joins the guild, the bot posts that message in the designated channel, personalized with the new
member's name and the guild's current member count. The operator chooses between plain text and a
fixed-layout card carrying a colour and the joining member's avatar. They can preview the result
before saving it and can disable greetings without losing the configured text.

**Why this priority**: Highest-frequency, lowest-risk automation, and the shortest path to a guild
seeing value from installing the bot. It exercises the configuration store, the permission model,
the template renderer, and the safe-output path that every other story depends on, making it the
natural foundation slice.

**Independent Test**: Install the bot in a test guild, configure a welcome message and channel, join
with a second account, and observe the rendered greeting. Delivers value with no other story built.

**Acceptance Scenarios**:

1. **Given** greetings are enabled with a configured channel and template, **When** a new member
   joins the guild, **Then** the bot posts the rendered message in that channel within 5 seconds of
   the join event.
2. **Given** a template containing the member-name placeholder, **When** a member whose display name
   contains an `@everyone` string joins, **Then** the posted message displays that name as inert
   text and notifies no one other than the joining member.
3. **Given** greetings are enabled, **When** the configured channel has been deleted or the bot has
   lost permission to post in it, **Then** the bot suppresses the message, records the failure, and
   surfaces the reason to the operator on the next configuration inspection.
4. **Given** an operator is editing the template, **When** they request a preview, **Then** the bot
   renders the message with sample values visible only to that operator without posting publicly.
5. **Given** greetings are disabled, **When** a new member joins, **Then** no message is posted and
   the stored template is retained unchanged.
5a. **Given** the card presentation is selected, **When** a member joins, **Then** the greeting is
    posted as a card carrying the operator's chosen colour and the joining member's own avatar, with
    the same placeholder substitution as plain text.
5b. **Given** the card presentation is selected, **When** the joining member has no avatar of their
    own, **Then** the card is posted without one rather than failing or leaving a broken image.
5c. **Given** an operator supplies an image address for the card, **When** they save, **Then** it is
    rejected — the card carries no operator-supplied imagery.
6. **Given** a member joins, leaves, and rejoins within a short window, **Then** the bot posts a
   greeting only once per join event but MUST NOT post more than a configured maximum of greetings
   per minute for the guild.

---

### User Story 2 - Self-service temporary voice channels (Priority: P2)

A guild operator designates an existing voice channel as the hub. When a member joins the hub, the
bot creates a voice channel for them, moves them into it, and grants them control over it. The
member never types anything — joining the hub is the whole interaction. When their channel becomes
empty, the bot deletes it automatically, leaving no residue in the guild's channel list.

**Why this priority**: The highest-value differentiator for active voice communities and entirely
self-contained — it depends on no external service. Ranked below greetings because it carries
meaningfully higher abuse and resource-exhaustion risk and therefore needs the rate-limiting and
audit substrate that Story 1 establishes.

**Independent Test**: Designate a hub channel in a test guild, join it as a non-privileged member,
confirm a channel is created and the member is placed in it, then leave and confirm the channel is
removed.

**Acceptance Scenarios**:

1. **Given** a hub channel is designated, **When** a member joins the hub, **Then** a new voice
   channel is created in the configured category and the member is moved into it within 3 seconds,
   and the member does not remain sitting in the hub.
2. **Given** a member owns a temporary channel, **When** the last occupant leaves it, **Then** the
   bot deletes the channel within 30 seconds.
3. **Given** a member owns a temporary channel, **When** they rename it, set a user limit, or lock
   it to specific members, **Then** the change applies only to their own channel and to no other.
4. **Given** the guild is at or near the platform limit of 500 channels, **When** a member joins the
   hub, **Then** creation is refused, the member is told why, they are removed from the hub rather
   than left waiting in it, and no partial channel is left behind.
5. **Given** a member repeatedly joins and leaves the hub, **When** they exceed the configured
   per-member creation rate, **Then** further creation is refused until the window resets, the
   refusal is recorded in the audit log, and the member is told why.
6. **Given** the bot restarts while temporary channels exist, **When** it reconnects, **Then** it
   reconciles known temporary channels and deletes those that are empty.
7. **Given** a temporary channel's owner leaves while others remain, **When** ownership transfer is
   configured, **Then** control passes to another occupant rather than the channel becoming
   unmanageable.
8. **Given** the bot creates a channel but cannot move the member into it, **When** the move fails,
   **Then** the empty channel is removed rather than left behind, and the member is told why.
9. **Given** the designated hub channel has been deleted in Discord, **When** the operator next
   inspects the configuration, **Then** the feature is shown as misconfigured with the cause, and no
   creation is attempted.
10. **Given** a member is moved into their new channel, **When** they later rejoin the hub while
    still owning a channel, **Then** they are returned to the channel they already own rather than a
    second one being created.

---

### User Story 3 - Scheduled channel messages (Priority: P3)

A guild operator schedules a message to be posted automatically in a chosen channel at a chosen
time, either once or repeating daily or weekly. Times are expressed in the guild's own timezone, so
"09:00" means nine in the morning for that community regardless of where the bot runs. The operator
can list, edit, and cancel scheduled messages, and can see when each will next be delivered.

**Why this priority**: Valuable for announcements and recurring rituals, but it serves operators
rather than every member, and it is the story most sensitive to the scheduling-semantics question
still open below. Sequenced after the two stories whose behavior is fully determined.

**Independent Test**: Schedule a message a few minutes out in a test guild, confirm it posts at the
expected time, then schedule and cancel another and confirm it does not post.

**Acceptance Scenarios**:

1. **Given** an operator schedules a message for a future time, **When** that time arrives, **Then**
   the bot posts the message in the specified channel within 60 seconds of the scheduled instant.
2. **Given** a scheduled message exists, **When** the operator lists scheduled messages, **Then**
   each entry shows its target channel, its content, and its next delivery time in an unambiguous,
   timezone-qualified form.
3. **Given** a scheduled message exists, **When** the operator cancels it, **Then** it is not
   delivered and is removed from the listing.
3a. **Given** a daily or weekly schedule, **When** one occurrence has been delivered, **Then** the
    listing shows the next occurrence and the schedule continues until cancelled.
3b. **Given** a daily schedule set for a local time that does not exist on the day the clocks move
    forward, **When** that day arrives, **Then** the message is delivered exactly once, at the first
    instant the local clock reaches or passes that time.
3c. **Given** a daily schedule set for a local time that occurs twice on the day the clocks move
    back, **When** that day arrives, **Then** the message is delivered exactly once, at the first of
    the two occurrences.
3d. **Given** a guild changes its configured timezone, **When** the change is saved, **Then**
    existing repeating schedules keep their stated local time and their next occurrence is
    recalculated and shown.
4. **Given** the bot was offline at a scheduled delivery instant, **When** it restarts, **Then** it
   delivers the missed occurrence if it is less than 15 minutes late and otherwise skips that
   occurrence, recording the skip. A skipped occurrence of a repeating schedule does not cancel the
   schedule; the next occurrence proceeds normally.
5. **Given** the target channel has been deleted or the bot cannot post in it, **When** delivery is
   attempted, **Then** the failure is recorded, the operator is notified, and the schedule is
   suspended rather than retried indefinitely.
6. **Given** a delivery has already occurred for a given scheduled instant, **When** the scheduler
   re-evaluates that instant for any reason, **Then** the message is not posted a second time.

---

### User Story 4 - Twitch live alerts (Priority: P4)

A guild operator subscribes the guild to one or more Twitch streamers. When a subscribed streamer
goes live, the bot posts an alert in a designated channel containing the stream title, the game or
category, and a link to the stream.

**Why this priority**: High community value, but it is the first story that introduces a dependency
on a third-party service, its credentials, and its failure modes. It is sequenced after the
self-contained stories so that external-integration risk lands on a working base.

**Independent Test**: Subscribe a test guild to a streamer that is currently offline, have that
streamer go live, and confirm exactly one alert is posted.

**Acceptance Scenarios**:

1. **Given** a guild is subscribed to a streamer, **When** that streamer starts a live broadcast,
   **Then** the bot posts one alert in the configured channel within 2 minutes of the broadcast
   starting.
2. **Given** an alert has been posted for a broadcast, **When** the stream briefly drops and
   reconnects within 30 minutes, **Then** no duplicate alert is posted for the same broadcast.
3. **Given** an operator subscribes to a streamer name that does not exist, **When** they confirm
   the subscription, **Then** the bot rejects it with a clear error and stores nothing.
4. **Given** the Twitch service is unreachable, **When** alerts would otherwise be evaluated,
   **Then** the bot degrades without crashing, retries with backoff, and does not emit false alerts
   when service is restored.
5. **Given** an operator lists subscriptions, **When** the listing is shown, **Then** each entry
   shows the streamer, the target channel, and the alert message template in use.
6. **Given** a streamer ends and restarts a broadcast after a long gap, **When** the new broadcast
   starts, **Then** a new alert is posted.

---

### User Story 5 - YouTube upload alerts (Priority: P5)

A guild operator subscribes the guild to one or more YouTube channels. When a subscribed YouTube
channel publishes a new video, the bot posts an alert in a designated Discord channel containing the
video title and a link.

**Why this priority**: Same shape and value as Twitch alerts but with a lower event rate and a
harder duplicate-suppression problem (edits and re-publishes of the same video). Placing it last
lets it reuse the subscription and deduplication machinery proven by Story 4.

**Independent Test**: Subscribe a test guild to a YouTube channel, publish a video on that channel,
and confirm exactly one alert is posted.

**Acceptance Scenarios**:

1. **Given** a guild is subscribed to a YouTube channel, **When** that channel publishes a new
   video, **Then** the bot posts one alert in the configured Discord channel within 10 minutes of
   publication.
2. **Given** an alert has been posted for a video, **When** the video's title or description is
   later edited, **Then** no second alert is posted for that video.
3. **Given** a guild newly subscribes to a YouTube channel with an existing back catalogue, **When**
   the subscription takes effect, **Then** no alerts are posted for videos published before the
   subscription.
4. **Given** a YouTube channel publishes a livestream or a short rather than a standard upload,
   **When** the operator has filtered that content type out, **Then** no alert is posted.
5. **Given** the YouTube service is unreachable or a quota is exhausted, **When** alerts would
   otherwise be evaluated, **Then** the bot degrades without crashing and resumes without emitting a
   burst of stale alerts.

---

### Edge Cases

**Permissions and platform state**

- The bot lacks permission to post in, create channels in, or move members into a configured target.
- A configured channel, category, or role is deleted after configuration.
- The bot is removed from a guild while schedules and subscriptions for it still exist.
- A guild reaches the platform maximum of 500 channels while temporary-channel creation is active.
- A rendered message exceeds the platform's 2,000-character message limit after placeholder
  substitution, or a card exceeds the different limits that apply to that presentation.
- A joining member has no avatar, or their avatar becomes unavailable between the join and the post.
- An operator attempts to place an image address in a greeting in order to make the bot fetch it.
- A channel name derived from a member's display name exceeds the platform's 100-character channel
  name limit or contains characters the platform rejects.

**Abuse and resource exhaustion**

- A raid floods the guild with joins, causing greeting output to be rate-limited or suppressed.
- A member repeatedly joins and leaves the hub channel to churn channel creation.
- A member is moved into a new channel but disconnects before the move completes.
- The hub channel itself is deleted, renamed, or moved while members are joining it.
- An operator configures a template containing `@everyone`, `@here`, or a role mention.
- An operator subscribes a guild to the maximum number of streamers or YouTube channels, and many
  guilds do so simultaneously, pushing total subscriptions past what the external services will
  answer within the latency targets.
- A single upstream identity — one streamer, one YouTube channel — is subscribed by a large number
  of guilds at once.
- A malicious operator schedules messages at a frequency intended to consume the bot's outbound
  budget at the expense of other guilds.

**Timing, ordering, and recovery**

- The bot is offline across a scheduled delivery instant, a stream start, or a video publication.
- Two instances of the bot run concurrently during a deployment, risking duplicate delivery.
- The upstream service reports a state change that was already processed (replayed event).
- A repeating schedule's local time falls inside a daylight-saving discontinuity — it does not exist
  on the day the clocks move forward, or occurs twice on the day they move back.
- A guild changes its timezone while repeating schedules are pending.
- The timezone rules themselves change upstream between the time a schedule is created and the time
  it fires.
- The clock jumps backward or forward on the host running the bot.

**Data lifecycle**

- A member leaves the guild while owning a temporary channel.
- A guild removes the bot and re-adds it within the 30-day window, so a prior configuration
  resurrects — it must be announced to the operator, not silently reinstated.
- A guild removes the bot and re-adds it after the 30-day window, finding its configuration gone.
- The bot is offline on the day a dormant guild's 30-day deletion falls due.
- A guild is removed and re-added repeatedly, which must not indefinitely postpone deletion.

## Requirements *(mandatory)*

### Functional Requirements

**Cross-cutting: configuration, permission, and safety**

- **FR-001**: System MUST maintain per-guild configuration isolated such that no guild's
  configuration, schedules, subscriptions, or audit records are readable or modifiable from another
  guild.
- **FR-002**: System MUST restrict every configuration-changing action to members the guild operator
  has authorized, and MUST deny the action by default when authorization cannot be positively
  established.
- **FR-003**: System MUST record an audit entry for every configuration change and every automated
  message delivery, capturing actor, guild, target, action, timestamp, and outcome.
- **FR-004**: System MUST render all operator-authored and member-derived text inertly, such that no
  posted message can trigger an `@everyone`, `@here`, or role notification unless the operator has
  been explicitly authorized to send such notifications and has opted in.
- **FR-005**: System MUST validate every operator-supplied message template at configuration time,
  rejecting templates that reference unknown placeholders or that cannot render within the
  platform's message length limit under worst-case substitution.
- **FR-006**: System MUST allow an operator to enable or disable each feature independently per
  guild, and MUST retain configuration across a disable/enable cycle.
- **FR-007**: System MUST report the reason for any suppressed or failed automated action to the
  operator through an inspectable status, rather than failing silently.
- **FR-008**: System MUST continue operating all other features for all other guilds when any single
  feature, guild, or external dependency fails.
- **FR-009**: System MUST permanently delete a guild's stored configuration, schedules,
  subscriptions, and derived state 30 days after the bot is removed from that guild. Within those 30
  days the data MUST be retained but dormant; after them it MUST be irrecoverable.
- **FR-009a**: System MUST perform no automated action for a guild the bot is not currently in. A
  dormant configuration MUST NOT deliver a scheduled message, post an alert, or create a channel,
  even where the underlying subscription remains stored.
- **FR-009b**: System MUST restore a guild's configuration intact when the bot is re-added within
  the 30-day window, and MUST tell the operator that a prior configuration was restored and when it
  was last active — so that a configuration reappearing is a visible event rather than a surprise.
- **FR-009c**: System MUST treat the 30-day deletion as unconditional. It MUST NOT be extended by
  re-removal, and MUST NOT depend on the bot being running at the moment it falls due; a deletion
  missed during an outage MUST be performed on the next start.
- **FR-010**: System MUST enforce a per-guild ceiling on outbound automated messages so that no
  single guild can exhaust the bot's delivery capacity for others.

**Welcome messages**

- **FR-011**: System MUST post a configured welcome message to a configured channel when a member
  joins a guild where greetings are enabled.
- **FR-012**: System MUST support placeholders in the welcome template for at minimum the joining
  member's mention, the joining member's display name, the guild name, and the guild's resulting
  member count.
- **FR-012a**: System MUST offer exactly two greeting presentations — plain text using the
  platform's own formatting, or a fixed-layout card carrying an operator-chosen colour and the
  joining member's avatar. Both MUST perform identical placeholder substitution, so the choice of
  presentation never changes what the message says.
- **FR-012b**: System MUST NOT accept an operator-supplied image address anywhere in a greeting, and
  MUST NOT fetch remote content chosen by a guild. The only image a card may carry is the joining
  member's own avatar, obtained from the platform.
- **FR-012c**: System MUST post a card without an avatar, rather than failing or displaying a broken
  image, when the joining member has none.
- **FR-012d**: System MUST validate that a card's content fits the platform's limits for that
  presentation, which differ from the plain-text message limit, and MUST reject a template that
  cannot render within them under worst-case substitution.
- **FR-013**: Operators MUST be able to preview a rendered welcome message privately before it takes
  effect.
- **FR-014**: System MUST post at most one welcome message per join event.
- **FR-015**: System MUST throttle welcome output when joins exceed a configured per-guild rate, and
  MUST record the throttling rather than dropping it silently.

**Temporary voice channels**

- **FR-016**: System MUST create a voice channel on behalf of a member who joins the guild's
  designated hub voice channel, and MUST move that member from the hub into the created channel.
- **FR-016a**: System MUST treat joining the hub as the sole activation mechanism. No command
  creates a temporary channel, so there is one creation path to authorize, rate-limit, and test.
- **FR-016b**: System MUST NOT leave a member waiting in the hub. When creation succeeds the member
  is moved out of it; when creation is refused or fails, the member is removed from the hub and told
  the reason.
- **FR-016c**: System MUST return a member who rejoins the hub while already owning a temporary
  channel to that existing channel rather than creating a second one.
- **FR-017**: System MUST delete a temporary voice channel once it has been empty for a configured
  grace period.
- **FR-018**: System MUST grant the creating member control over their own temporary channel —
  renaming, setting a participant limit, and restricting access — and MUST prevent that member from
  affecting any channel they do not own.
- **FR-019**: System MUST enforce a per-member and per-guild limit on concurrently held temporary
  channels and on creation rate.
- **FR-020**: System MUST refuse creation with an explanatory response when the guild is at the
  platform channel limit, and MUST NOT leave a partially created channel behind.
- **FR-020a**: System MUST remove a channel it created but could not move the member into, so that a
  failed creation never adds a permanent empty channel to the guild.
- **FR-020b**: System MUST report the temporary voice feature as misconfigured, and MUST attempt no
  creation, when the designated hub channel no longer exists or the bot cannot act on it.
- **FR-021**: System MUST reconcile temporary-channel state on restart, deleting orphaned empty
  channels it previously created.
- **FR-022**: System MUST sanitize any member-derived text used in a channel name to the platform's
  permitted character set and length.

**Scheduled messages**

- **FR-023**: Operators MUST be able to create a scheduled message specifying target channel,
  content, delivery time, and whether it fires once, daily, or weekly. No other recurrence pattern
  is supported in this version.
- **FR-023a**: System MUST interpret every scheduled time in the guild's configured timezone, taken
  from the IANA Time Zone Database, and MUST require that timezone to be set before a schedule can
  be created. Times MUST NOT be interpreted in the timezone of the host the bot runs on, so that
  moving the deployment never changes when a guild's messages arrive.
- **FR-023b**: System MUST deliver a repeating schedule exactly once for a local time that does not
  exist on a day the clocks move forward, at the first instant the local clock reaches or passes
  that time.
- **FR-023c**: System MUST deliver a repeating schedule exactly once for a local time that occurs
  twice on a day the clocks move back, at the first of the two occurrences.
- **FR-023d**: System MUST preserve the stated local time of existing schedules when a guild changes
  its timezone, and MUST recalculate and display their next occurrence.
- **FR-024**: Operators MUST be able to list, edit, and cancel scheduled messages for their guild.
- **FR-025**: System MUST deliver each scheduled message within 60 seconds of its scheduled instant.
- **FR-026**: System MUST deliver each scheduled instant exactly once, even across restarts,
  redeployments, or concurrent instances.
- **FR-027**: System MUST skip rather than deliver any occurrence whose scheduled instant passed
  more than 15 minutes ago, and MUST record the skip. Skipping an occurrence of a repeating schedule
  MUST NOT cancel or suspend that schedule.
- **FR-027a**: System MUST deliver at most one message per occurrence of a repeating schedule, and
  MUST NOT deliver a backlog of missed occurrences after an outage.
- **FR-028**: System MUST suspend a schedule and notify the operator after a delivery failure caused
  by a missing channel or insufficient permission, rather than retrying indefinitely.
- **FR-029**: System MUST display every scheduled time with an explicit, unambiguous timezone
  qualification, and MUST show the next occurrence of a repeating schedule as a concrete date and
  time rather than only as a pattern.

**Twitch live alerts**

- **FR-030**: Operators MUST be able to subscribe their guild to a named Twitch streamer, choose the
  destination channel, and customise the alert message.
- **FR-031**: System MUST post an alert within 2 minutes of a subscribed streamer starting a
  broadcast.
- **FR-032**: System MUST post at most one alert per broadcast, treating a reconnection within a
  configured window as the same broadcast.
- **FR-033**: System MUST validate a streamer's existence at subscription time and reject unknown
  names without storing them.
- **FR-034**: System MUST include the stream title, category, and a link to the broadcast in the
  alert.
- **FR-035**: Operators MUST be able to list and remove Twitch subscriptions.
- **FR-035a**: System MUST enforce a ceiling on Twitch subscriptions per guild, defaulting to 25,
  and MUST refuse a subscription beyond it with an explanatory message naming the limit. The ceiling
  MUST be operator-configurable so a deployment serving few guilds can raise it and one serving many
  can lower it without a code change.

**YouTube upload alerts**

- **FR-036**: Operators MUST be able to subscribe their guild to a YouTube channel, choose the
  destination Discord channel, and customise the alert message.
- **FR-037**: System MUST post an alert within 10 minutes of a subscribed YouTube channel publishing
  a new video.
- **FR-038**: System MUST post at most one alert per video, including when the video is subsequently
  edited or re-announced by the upstream service.
- **FR-039**: System MUST NOT post alerts for videos published before the subscription was created.
- **FR-040**: System MUST allow operators to exclude content types they do not want announced, at
  minimum livestreams and short-form videos.
- **FR-041**: System MUST validate a YouTube channel's existence at subscription time and reject
  unknown channels without storing them.
- **FR-042**: Operators MUST be able to list and remove YouTube subscriptions.
- **FR-042a**: System MUST enforce a ceiling on YouTube subscriptions per guild, defaulting to 25,
  on the same terms as FR-035a.
- **FR-042b**: System MUST NOT accept a new subscription of either kind when doing so would push the
  deployment's total subscription count past what its configured external-service budgets can
  evaluate within the latency targets in SC-005. The refusal MUST name the deployment ceiling as the
  cause rather than appearing to be a fault in the guild's own configuration.
- **FR-043**: System MUST NOT emit a backlog burst of alerts after an outage; alerts for events
  older than a documented staleness threshold MUST be dropped and recorded.

### Key Entities *(include if feature involves data)*

- **Guild Configuration**: The per-guild root of all settings. Holds which features are enabled,
  which members or roles may administer the bot, the guild's timezone, and the per-guild rate
  ceilings. Owns every entity
  below; deleted when the bot leaves the guild.
- **Welcome Setting**: The greeting template, its destination channel, its presentation (plain text
  or card), the card's colour when that presentation is chosen, and its enabled state. Exactly one
  per guild.
- **Temporary Voice Setting**: The designated hub voice channel, the category new channels are
  placed in, the channel-name pattern, the empty-channel grace period, and the per-member
  concurrency and rate limits. Exactly one per guild. Invalid when the hub channel no longer
  exists.
- **Temporary Voice Channel**: A live record of a channel the bot created — its owner, its creation
  time, and its current occupancy — used to delete it when empty and to reconcile state after a
  restart. Transient; exists only while the channel does.
- **Scheduled Message**: A pending delivery — destination channel, content, the local time it fires,
  its recurrence (once, daily, or weekly, with the weekday when weekly), its computed next
  occurrence, enabled/suspended state, and the identifier of the last occurrence successfully
  delivered. The last-delivered occurrence is what makes FR-026's exactly-once guarantee hold across
  restarts. Many per guild.
- **Stream Subscription**: A guild's interest in a Twitch streamer — the streamer identity, the
  destination channel, the alert template, and the identifier of the most recently announced
  broadcast, used to suppress duplicates. Many per guild.
- **Video Subscription**: A guild's interest in a YouTube channel — the channel identity, the
  destination Discord channel, the alert template, the content-type filter, the subscription start
  instant, and the set of recently announced video identifiers used to suppress duplicates. Many per
  guild.
- **Delivery Record**: An append-only entry establishing that a given automated action (greeting,
  scheduled instant, broadcast alert, video alert) has already been performed, so it is performed
  exactly once. Also serves the audit requirement in FR-003.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A guild operator can configure any one of the five features end-to-end in under 3
  minutes without consulting external documentation.
- **SC-002**: 99% of welcome messages appear within 5 seconds of the member joining, in both
  presentations.
- **SC-002a**: Zero greetings cause the bot to fetch remote content chosen by a guild, verified by
  observing all outbound requests while exercising every greeting configuration.
- **SC-003**: 99% of temporary voice channels are created and the requesting member placed in them
  within 3 seconds of activation, and 99% are removed within 30 seconds of becoming empty.
- **SC-004**: 99% of scheduled messages are delivered within 60 seconds of their scheduled instant.
- **SC-004a**: Across a full year of simulated time, every daily and weekly schedule fires exactly
  once per intended occurrence, including on both daylight-saving transition days, verified by
  replaying a year against a timezone that observes them.
- **SC-005**: 95% of Twitch alerts appear within 2 minutes of the broadcast starting, and 95% of
  YouTube alerts within 10 minutes of publication, measured with every guild at its default
  subscription ceiling.
- **SC-005a**: The stated alert latencies hold at 1,000 guilds each holding 25 Twitch and 25 YouTube
  subscriptions, without exceeding either external service's request budget, verified by load
  modelling before implementation and by measurement after.
- **SC-006**: Zero duplicate announcements across a measurement period spanning at least one full
  restart and one deployment — every broadcast, video, scheduled instant, and join produces exactly
  one message.
- **SC-007**: Zero unintended mass notifications: no automated message triggers an `@everyone`,
  `@here`, or role notification that the operator did not explicitly configure and was not
  authorized to send.
- **SC-008**: No temporary voice channel persists more than 5 minutes after its last occupant leaves,
  including across a bot restart, verified over a 7-day soak.
- **SC-009**: The bot sustains 1,000 guilds and 10,000 concurrent members without any per-guild
  latency target above degrading beyond its stated threshold.
- **SC-010**: A single guild's misconfiguration, abuse, or external-service failure never degrades
  service for another guild, verified by fault injection.
- **SC-011**: Outages of either external content service are survived without crash, without false
  alerts on recovery, and without a backlog burst — verified by injecting a 1-hour outage.
- **SC-012**: 100% of automated deliveries and configuration changes are attributable in the audit
  record to an actor, a target, and an outcome.
- **SC-013**: No automated action of any kind is performed for a guild the bot is not in, verified
  by removing the bot from a guild holding active schedules and subscriptions and observing for the
  full dormancy window.
- **SC-014**: A guild's data is irrecoverable 30 days after the bot is removed, verified by
  inspection of every store after the window elapses, including when the bot was offline on the day
  the deletion fell due.

## Assumptions

**Scope boundaries**

- v1 targets the five features named above only. Levelling/XP, moderation, autoroles, custom
  commands, music, and reaction roles — all present in comparable products — are explicitly out of
  scope.
- The bot is self-hosted by an operator who controls its credentials and its datastore. A public
  multi-tenant hosted offering is out of scope for v1, though the per-guild isolation requirements
  are written so as not to foreclose it.
- Configuration of every feature below is performed through the web management application specified
  in [002-web-management-dashboard](../002-web-management-dashboard/spec.md). Requirements in this
  specification describe the bot's behavior; requirements governing who may configure it and how
  they reach it live in that specification. In-Discord commands are deliberately not a
  configuration surface: the only exceptions are a per-feature emergency disable and the temporary
  voice channel owner controls in FR-018, which act on a live channel its owner is occupying.
- Leave/farewell messages are out of scope; only join greetings are in scope.
- Welcome messages are posted to a guild channel. Direct-message greetings are out of scope for v1.
- Greetings offer two presentations and no more. A fully designable card — arbitrary titles, fields,
  footers and images — is out of scope: it is a disproportionately large editing interface for the
  dashboard, and operator-supplied image addresses would make the bot fetch remote content chosen by
  a guild, which is a capability worth not having. A colour and the member's own avatar deliver most
  of the visual effect with none of that exposure.

**Reasonable defaults adopted where the description was silent**

- Temporary voice channels are deleted after a short grace period rather than immediately, so that a
  member reconnecting after a brief drop does not lose their channel.
- Alert messages are customisable per subscription, following the expectation set by comparable
  products; a sensible default template ships so that configuration is a single step.
- Each guild may subscribe to up to 25 Twitch streamers and 25 YouTube channels by default, and the
  ceiling is operator-configurable. This covers a community following its own streamers and a few
  affiliates, which is what the feature is for. The number is not arbitrary: total subscriptions
  across all guilds, divided by what each external platform will answer per unit time, is what
  determines achievable alert latency, so an unbounded ceiling would turn the 2-minute Twitch target
  into an unenforceable aspiration for every guild at once.
- Many guilds subscribing to the same upstream identity are expected to cost roughly what one guild
  costs, so the binding constraint is the number of distinct streamers and channels followed across
  the deployment rather than the number of subscriptions.
- Timezone rules come from the IANA Time Zone Database rather than being hardcoded, so that a
  jurisdiction changing its daylight-saving policy is handled by updating that data rather than by
  changing the bot. Rules are resolved at the moment an occurrence is computed, not when the
  schedule was created.
- Daily and weekly cover effectively every real use of this feature — a daily check-in, a weekly
  event announcement. Monthly is excluded because "the 31st" has no meaning in February, and
  arbitrary repeat rules are excluded because they multiply daylight-saving handling across every
  schedule independently while being hostile to configure.
- Duplicate suppression is required for every announcement type; an at-most-once delivery guarantee
  is preferred over at-least-once, because a duplicate mass notification is more damaging to a guild
  than a missed one.
- Configuration is administered by guild members holding an operator-designated role, defaulting to
  members with guild-management authority.
- Removal of the bot begins a 30-day dormancy rather than an immediate erasure. The grace period
  exists because an accidental removal would otherwise destroy every schedule, subscription and
  template a community had built, with no way back. Thirty days is long enough to cover that and a
  brief trial of an alternative, and short enough to remain ordinary service continuity rather than
  indefinite retention of data belonging to communities that no longer use the bot. Dormant data
  does nothing (FR-009a); it is inert storage awaiting either restoration or deletion.

**Dependencies**

- Requires a registered Discord application with a bot user, and the privileged gateway intent
  necessary to observe member joins. The operator must enable that intent; greetings cannot function
  without it.
- Requires credentials for the Twitch platform and for the YouTube platform. Each alert feature is
  independently disableable so that a guild lacking one set of credentials can still run the rest.
- Both external content platforms impose quotas and rate limits that constrain how frequently
  subscriptions can be evaluated; the stated alert latency targets assume operation within those
  quotas at the subscription ceilings above. The deployment MUST refuse new subscriptions rather
  than silently degrade every guild's latency once that budget is reached (FR-042b).
- Platform limits assumed and designed against: 500 channels per guild, 2,000 characters per
  message, 100 characters per channel name. Card presentations carry their own, different limits,
  which FR-012d requires be validated separately rather than assumed equal to the message limit.

**Open decisions**

- **RESOLVED (2026-09-16)**: Configuration surface — a web management application is mandatory and
  is specified separately in [002-web-management-dashboard](../002-web-management-dashboard/spec.md).
  Server owners, administrators, and members holding a designated manager role administer the
  features in this specification through that application. Whether in-Discord commands additionally
  provide full parity remains open and is tracked in that specification.
- **RESOLVED (2026-09-16)**: Temporary voice channel activation — a member joins a designated hub
  voice channel and the bot creates and moves them into their own channel (FR-016, FR-016a). This is
  the pattern members already recognise and it requires no typing at the moment they want to talk.
  There is exactly one creation path, so there is one place to authorize and rate-limit. The abuse
  case is join/leave churn against the hub, bounded by the per-member concurrency and rate limits in
  FR-019 that the feature needs under any trigger design.
- **RESOLVED (2026-09-16)**: Scheduled-message recurrence and timezone — one-time, daily, and weekly
  repeats, interpreted in a per-guild timezone (FR-023, FR-023a). Daylight-saving transitions are
  resolved by explicit rules rather than left to chance: a non-existent local time fires at the next
  existing instant (FR-023b), an ambiguous one fires on its first occurrence (FR-023c). These are
  the two days a year where a scheduling bug silently drops or doubles a message, so the behavior is
  stated as a requirement and tested by SC-004a rather than being discovered in production.
