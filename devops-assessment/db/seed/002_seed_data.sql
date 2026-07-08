-- 002_seed_data.sql
-- Seeds hotel_bookings with 120 rows spread across multiple cities,
-- organizations, and statuses, with created_at relative to NOW() so the
-- "last 30 days" query in the assessment always has real matches,
-- regardless of when this is run.

DO $$
DECLARE
    v_cities   TEXT[] := ARRAY['delhi', 'mumbai', 'bangalore', 'chennai', 'hyderabad'];
    v_statuses TEXT[] := ARRAY['confirmed', 'cancelled', 'completed', 'pending'];
    v_orgs     UUID[] := ARRAY[
        gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
        gen_random_uuid(), gen_random_uuid()
    ];
    v_booking_id UUID;
    i INT;
BEGIN
    FOR i IN 1..120 LOOP
        v_booking_id := gen_random_uuid();

        INSERT INTO hotel_bookings (
            id, org_id, hotel_id, city, checkin_date, checkout_date,
            amount, status, created_at
        )
        VALUES (
            v_booking_id,
            v_orgs[1 + (i % array_length(v_orgs, 1))],
            'HOTEL-' || lpad(((i % 15) + 1)::text, 3, '0'),
            v_cities[1 + (i % array_length(v_cities, 1))],
            (CURRENT_DATE - ((i % 60) || ' days')::interval)::date,
            (CURRENT_DATE - ((i % 60) || ' days')::interval + interval '2 days')::date,
            (1500 + (i * 37) % 9000)::numeric(12, 2),
            v_statuses[1 + (i % array_length(v_statuses, 1))],
            -- Spread created_at across the last 45 days so the "last 30 days"
            -- filter has a realistic mix of in-range and out-of-range rows.
            now() - ((i % 45) || ' days')::interval - ((i % 24) || ' hours')::interval
        );

        -- Add a couple of lifecycle events for roughly half the bookings.
        IF i % 2 = 0 THEN
            INSERT INTO booking_events (booking_id, event_type, payload, created_at)
            VALUES
                (v_booking_id, 'booking_created', jsonb_build_object('source', 'seed'), now() - ((i % 45) || ' days')::interval),
                (v_booking_id, 'payment_confirmed', jsonb_build_object('source', 'seed'), now() - ((i % 45) || ' days')::interval + interval '1 hour');
        END IF;
    END LOOP;
END $$;
