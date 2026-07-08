-- 001_create_tables.sql
-- Core schema for the hotel booking reliability assessment.

CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- for gen_random_uuid()

CREATE TABLE IF NOT EXISTS hotel_bookings (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        UUID NOT NULL,
    hotel_id      VARCHAR(100) NOT NULL,
    city          VARCHAR(100) NOT NULL,
    checkin_date  DATE NOT NULL,
    checkout_date DATE NOT NULL,
    amount        NUMERIC(12, 2) NOT NULL,
    status        VARCHAR(50) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS booking_events (
    id         BIGSERIAL PRIMARY KEY,
    booking_id UUID NOT NULL REFERENCES hotel_bookings (id) ON DELETE CASCADE,
    event_type VARCHAR(100) NOT NULL,
    payload    JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Indexing strategy for the target query:
--
--   SELECT org_id, status, COUNT(*), SUM(amount)
--   FROM hotel_bookings
--   WHERE city = 'delhi'
--     AND created_at >= NOW() - INTERVAL '30 days'
--   GROUP BY org_id, status;
--
-- The WHERE clause filters on (city, created_at), and the GROUP BY needs
-- (org_id, status). A single composite B-tree index with city and created_at
-- as the leading columns lets Postgres do an index range scan instead of a
-- sequential scan, since city is an equality filter and created_at is a
-- range filter — equality columns should lead a composite index, followed
-- by the range column. org_id and status are included (INCLUDE) purely to
-- allow an index-only scan for the aggregation, avoiding a heap fetch for
-- every matching row.
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);

-- Supports lookups of all events for a given booking (used by the app layer
-- and by the restore-verification query in scripts/restore.sh).
CREATE INDEX IF NOT EXISTS idx_booking_events_booking_id
    ON booking_events (booking_id);
