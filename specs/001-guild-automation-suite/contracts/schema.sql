-- Contract: PostgreSQL schema for the Guild Automation Suite (spec 001).
-- Applied by the gaea-migrate binary using a privileged account separate from the
-- account the services run as (ADR-0004, and the constitution's privilege-isolation rule).
-- This file is the contract; the authoritative migrations live in crates/gaea-store/migrations/.

CREATE TYPE greeting_presentation AS ENUM ('plain', 'card');
CREATE TYPE recurrence_kind       AS ENUM ('once', 'daily', 'weekly');
CREATE TYPE schedule_state        AS ENUM ('active', 'suspended');
CREATE TYPE delivery_kind         AS ENUM ('greeting', 'scheduled', 'stream_alert',
                                           'video_alert', 'voice_created', 'config_change');
CREATE TYPE delivery_outcome      AS ENUM ('delivered', 'skipped', 'suppressed', 'failed');

-- Root of all configuration. Everything below cascades from here, which is how
-- FR-001's cross-guild isolation is a schema property rather than a convention.
CREATE TABLE guild (
    id                        BIGINT PRIMARY KEY,
    timezone                  TEXT        NOT NULL,
    removed_at                TIMESTAMPTZ,
    purge_after               TIMESTAMPTZ,
    max_greetings_per_minute  INTEGER     NOT NULL DEFAULT 10,
    max_messages_per_minute   INTEGER     NOT NULL DEFAULT 30,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- FR-009: dormancy and its deletion date are set and cleared together.
    CONSTRAINT dormancy_coherent CHECK ((removed_at IS NULL) = (purge_after IS NULL))
);

-- FR-009c: the purge sweep reconciles against a stored date, so a deletion missed
-- while the bot was offline is performed on the next start.
CREATE INDEX guild_purge_due ON guild (purge_after) WHERE purge_after IS NOT NULL;

CREATE TABLE welcome_setting (
    guild_id      BIGINT PRIMARY KEY REFERENCES guild(id) ON DELETE CASCADE,
    enabled       BOOLEAN               NOT NULL DEFAULT false,
    channel_id    BIGINT                NOT NULL,
    template      TEXT                  NOT NULL,
    presentation  greeting_presentation NOT NULL DEFAULT 'plain',
    card_colour   INTEGER,
    -- FR-012b: there is no column for an operator-supplied image address, so the bot
    -- cannot be made to fetch remote content chosen by a guild.
    CONSTRAINT colour_only_for_card CHECK (card_colour IS NULL OR presentation = 'card')
);

CREATE TABLE temporary_voice_setting (
    guild_id              BIGINT PRIMARY KEY REFERENCES guild(id) ON DELETE CASCADE,
    enabled               BOOLEAN NOT NULL DEFAULT false,
    hub_channel_id        BIGINT  NOT NULL,
    category_id           BIGINT,
    name_pattern          TEXT    NOT NULL,
    empty_grace_seconds   INTEGER NOT NULL DEFAULT 30,
    max_per_member        INTEGER NOT NULL DEFAULT 1,
    creations_per_window  INTEGER NOT NULL DEFAULT 3,
    window_seconds        INTEGER NOT NULL DEFAULT 600
);

CREATE TABLE temporary_voice_channel (
    channel_id   BIGINT PRIMARY KEY,
    guild_id     BIGINT      NOT NULL REFERENCES guild(id) ON DELETE CASCADE,
    owner_id     BIGINT      NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    empty_since  TIMESTAMPTZ
);

-- FR-016c: a member rejoining the hub while owning a channel is returned to it
-- rather than given a second one.
CREATE UNIQUE INDEX one_channel_per_owner ON temporary_voice_channel (guild_id, owner_id);
-- FR-017: drives deletion of channels empty beyond the grace period.
CREATE INDEX voice_empty_since ON temporary_voice_channel (empty_since)
    WHERE empty_since IS NOT NULL;

CREATE TABLE scheduled_message (
    id                          UUID PRIMARY KEY,
    guild_id                    BIGINT           NOT NULL REFERENCES guild(id) ON DELETE CASCADE,
    channel_id                  BIGINT           NOT NULL,
    content                     TEXT             NOT NULL,
    recurrence                  recurrence_kind  NOT NULL,
    -- The local time the operator chose, never a pre-resolved instant. Occurrences are
    -- computed against the guild's IANA zone when needed, so FR-023b/c can apply.
    local_time                  TIME             NOT NULL,
    weekday                     SMALLINT,
    fire_date                   DATE,
    next_occurrence             TIMESTAMPTZ      NOT NULL,
    -- FR-026: the exactly-once anchor. Set in the same transaction that sends.
    last_delivered_occurrence   TIMESTAMPTZ,
    state                       schedule_state   NOT NULL DEFAULT 'active',
    suspend_reason              TEXT,
    created_at                  TIMESTAMPTZ      NOT NULL DEFAULT now(),
    CONSTRAINT weekday_iff_weekly CHECK ((recurrence = 'weekly') = (weekday IS NOT NULL)),
    CONSTRAINT date_iff_once      CHECK ((recurrence = 'once')   = (fire_date IS NOT NULL)),
    CONSTRAINT weekday_range      CHECK (weekday IS NULL OR weekday BETWEEN 0 AND 6),
    CONSTRAINT suspended_has_reason CHECK (state <> 'suspended' OR suspend_reason IS NOT NULL)
);

-- The claim queue. Delivery takes rows with FOR UPDATE SKIP LOCKED, which is what makes
-- FR-026 hold across restarts, redeployments and concurrent instances.
CREATE INDEX schedule_due ON scheduled_message (next_occurrence) WHERE state = 'active';

CREATE TABLE stream_subscription (
    id                           UUID PRIMARY KEY,
    guild_id                     BIGINT      NOT NULL REFERENCES guild(id) ON DELETE CASCADE,
    channel_id                   BIGINT      NOT NULL,
    broadcaster_id               TEXT        NOT NULL,
    template                     TEXT        NOT NULL,
    last_announced_broadcast_id  TEXT,
    last_announced_at            TIMESTAMPTZ,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (guild_id, broadcaster_id)
);

-- FR-042b: the deployment ceiling counts DISTINCT upstream identities, because many
-- guilds following one streamer costs roughly what one guild costs.
CREATE INDEX stream_by_broadcaster ON stream_subscription (broadcaster_id);

CREATE TABLE video_subscription (
    id                  UUID PRIMARY KEY,
    guild_id            BIGINT      NOT NULL REFERENCES guild(id) ON DELETE CASCADE,
    channel_id          BIGINT      NOT NULL,
    youtube_channel_id  TEXT        NOT NULL,
    template            TEXT        NOT NULL,
    -- FR-039: nothing published before this instant is ever announced.
    subscribed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    exclude_livestreams BOOLEAN     NOT NULL DEFAULT true,
    exclude_shorts      BOOLEAN     NOT NULL DEFAULT true,
    -- A lease that lapses without renewal is a silent permanent failure.
    lease_expires_at    TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (guild_id, youtube_channel_id)
);

CREATE INDEX video_by_channel       ON video_subscription (youtube_channel_id);
CREATE INDEX video_lease_renewal_due ON video_subscription (lease_expires_at)
    WHERE lease_expires_at IS NOT NULL;

-- FR-038: at most one alert per video, including after an edit or re-announce.
-- A child table rather than an array, so this is a constraint rather than a search.
CREATE TABLE announced_video (
    subscription_id  UUID        NOT NULL REFERENCES video_subscription(id) ON DELETE CASCADE,
    video_id         TEXT        NOT NULL,
    announced_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (subscription_id, video_id)
);

-- Append-only. Serves both the audit obligation (FR-003, Principle VI) and the
-- exactly-once guarantees.
CREATE TABLE delivery_record (
    id           BIGSERIAL PRIMARY KEY,
    guild_id     BIGINT           NOT NULL REFERENCES guild(id) ON DELETE CASCADE,
    kind         delivery_kind    NOT NULL,
    subject      TEXT             NOT NULL,
    actor_id     BIGINT,
    outcome      delivery_outcome NOT NULL,
    reason       TEXT,
    occurred_at  TIMESTAMPTZ      NOT NULL DEFAULT now()
);

-- This is what makes "exactly once" a database constraint rather than an application
-- hope — for greetings, scheduled instants, broadcasts and videos alike.
CREATE UNIQUE INDEX delivered_once
    ON delivery_record (guild_id, kind, subject)
    WHERE outcome = 'delivered';

-- Rate ceilings are evaluated against this table within a window rather than held in
-- memory, so a restart cannot reset a guild's consumption (FR-010, FR-015, FR-019).
CREATE INDEX delivery_window ON delivery_record (guild_id, kind, occurred_at DESC);

-- Retention: 90 days by default, operator-configurable (FR-049 of spec 002).
CREATE INDEX delivery_retention ON delivery_record (occurred_at);
