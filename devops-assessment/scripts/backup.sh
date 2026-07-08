set -euo pipefail

DB_SERVICE="db"
DB_NAME="hotelbook"
DB_USER="app_admin"
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/backups"

mkdir -p "$BACKUP_DIR"

timestamp=$(date +"%Y%m%d_%H%M%S")
backup_file="${BACKUP_DIR}/hotelbook_backup_${timestamp}.sql"

echo "Checking that the '${DB_SERVICE}' container is running..."
if ! docker compose ps --status running --services | grep -q "^${DB_SERVICE}$"; then
    echo "ERROR: '${DB_SERVICE}' service is not running. Start it first with:"
    echo "  docker compose up -d"
    exit 1
fi

echo "Creating backup: ${backup_file}"
docker compose exec -T "${DB_SERVICE}" pg_dump \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    --no-owner \
    --no-privileges \
    > "${backup_file}"

if [ -s "${backup_file}" ]; then
    size=$(du -h "${backup_file}" | cut -f1)
    echo "Backup completed successfully: ${backup_file} (${size})"
else
    echo "ERROR: Backup file is empty. Something went wrong."
    rm -f "${backup_file}"
    exit 1
fi
