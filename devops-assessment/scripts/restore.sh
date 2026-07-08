#!/usr/bin/env bash
# restore.sh
# Restores a backup produced by backup.sh into a FRESH database
# (hotelbook_restore_test) inside the same running "db" container,
# so restore can be verified without touching the live "hotelbook" database.
#
# Usage:
#   ./scripts/restore.sh                     # restores the most recent backup
#   ./scripts/restore.sh path/to/backup.sql  # restores a specific backup file

set -euo pipefail

DB_SERVICE="db"
DB_USER="app_admin"
RESTORE_DB="hotelbook_restore_test"
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backups"

if ! docker compose ps --status running --services | grep -q "^${DB_SERVICE}$"; then
    echo "ERROR: '${DB_SERVICE}' service is not running. Start it first with:"
    echo "  docker compose up -d"
    exit 1
fi

if [ "$#" -ge 1 ]; then
    backup_file="$1"
else
    backup_file=$(ls -t "${BACKUP_DIR}"/hotelbook_backup_*.sql 2>/dev/null | head -n1 || true)
    if [ -z "${backup_file}" ]; then
        echo "ERROR: No backup files found in ${BACKUP_DIR}. Run ./scripts/backup.sh first."
        exit 1
    fi
fi

if [ ! -f "${backup_file}" ]; then
    echo "ERROR: Backup file not found: ${backup_file}"
    exit 1
fi

echo "Restoring '${backup_file}' into a fresh database: ${RESTORE_DB}"

echo "Dropping old test database if it exists..."
docker compose exec -T "${DB_SERVICE}" psql -U "${DB_USER}" -d postgres \
    -c "DROP DATABASE IF EXISTS ${RESTORE_DB};"

echo "Creating fresh database: ${RESTORE_DB}"
docker compose exec -T "${DB_SERVICE}" psql -U "${DB_USER}" -d postgres \
    -c "CREATE DATABASE ${RESTORE_DB};"

echo "Loading backup into ${RESTORE_DB}..."
docker compose exec -T "${DB_SERVICE}" psql -U "${DB_USER}" -d "${RESTORE_DB}" \
    < "${backup_file}"

echo ""
echo "Verifying restore..."
echo "----------------------------------------------------------"

booking_count=$(docker compose exec -T "${DB_SERVICE}" psql -U "${DB_USER}" -d "${RESTORE_DB}" \
    -tAc "SELECT COUNT(*) FROM hotel_bookings;")
event_count=$(docker compose exec -T "${DB_SERVICE}" psql -U "${DB_USER}" -d "${RESTORE_DB}" \
    -tAc "SELECT COUNT(*) FROM booking_events;")
index_count=$(docker compose exec -T "${DB_SERVICE}" psql -U "${DB_USER}" -d "${RESTORE_DB}" \
    -tAc "SELECT COUNT(*) FROM pg_indexes WHERE tablename = 'hotel_bookings';")

echo "hotel_bookings rows restored : ${booking_count}"
echo "booking_events rows restored : ${event_count}"
echo "indexes present on hotel_bookings : ${index_count}"
echo "----------------------------------------------------------"

if [ "${booking_count}" -gt 0 ] && [ "${index_count}" -gt 0 ]; then
    echo "Restore verified successfully: data and indexes are present in ${RESTORE_DB}."
else
    echo "WARNING: Restore completed but verification counts look wrong. Inspect manually:"
    echo "  docker compose exec ${DB_SERVICE} psql -U ${DB_USER} -d ${RESTORE_DB}"
    exit 1
fi
