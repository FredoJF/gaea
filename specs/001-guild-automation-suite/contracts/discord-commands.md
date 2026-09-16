# Contract: In-Discord Command Surface

**Governed by**: FR-041, FR-042, FR-043 of [spec 002](../../002-web-management-dashboard/spec.md) and
[ADR-0003](../../../docs/adr/0003-process-topology-and-interaction-transport.md).

The dashboard is the sole configuration surface. Discord carries exactly two things, both shaped so
they cannot drift from it.

Interactions arrive over the gateway, not over HTTP. There is no interaction endpoint, so no Ed25519
verification path exists to attack.

## 1. Emergency feature disable

`/gaea disable <feature>` where feature ∈ {greetings, schedules, voice, twitch, youtube}

**Authorization**: guild owner, administrator, or a designated manager role. Default-deny.

**Semantics**: sets `enabled = false` for that feature in that guild. It can **only disable**. There
is no enable command and no command that changes any other setting, so a compromised Discord account
cannot use this surface to widen what the bot does (FR-042).

**Availability**: must work while the dashboard is entirely unreachable — this is the command's
whole reason to exist. It therefore touches only the database and the gateway, never the web
process.

**Response**: ephemeral, naming the feature disabled and stating that re-enabling happens in the
dashboard.

**Audit**: writes a `config_change` delivery record with the acting member, and the dashboard shows
on the affected feature's page that it was disabled, by whom, and when (FR-044).

**Failure**: if the database is unreachable the command reports failure explicitly. It must never
report success it cannot confirm.

## 2. Temporary voice channel owner controls

`/voice rename <name>` · `/voice limit <n>` · `/voice lock` · `/voice unlock` ·
`/voice transfer <member>`

**Authorization**: the invoking member must own the temporary channel they are currently connected
to. Not owning it, or not being connected, is a denial — and the denial message must not reveal
whether the channel exists or who owns it.

**Semantics**: acts on the live channel only. Touches no stored configuration, which is why it
cannot drift from the dashboard (FR-043).

**Validation**: `rename` sanitizes to the platform's 100-character limit and permitted character set
(FR-022). `limit` is bounded by the platform's own participant range.

**Rate limiting**: Discord limits channel name and topic edits to 2 per 10 minutes per channel. The
boundary's limiter absorbs this; the command reports honestly when a rename is deferred rather than
silently dropping it.

## Not present

No command configures greetings, schedules, subscriptions, or the voice hub. No command enables a
feature. No command reads another guild's state. This absence is the contract — adding a
configuration command would violate FR-041 and create a second authorization path to keep correct.
