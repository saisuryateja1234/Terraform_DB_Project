-- The query Part 5 asks us to optimize.
-- Run with EXPLAIN ANALYZE to see the index from
-- 001_create_tables.sql (idx_hotel_bookings_city_created_at) being used:
--
--   docker compose exec db psql -U app_admin -d hotelbook \
--     -c "EXPLAIN ANALYZE $(cat db/queries/target_query.sql)"

SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
