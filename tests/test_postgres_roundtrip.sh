#!/usr/bin/env bash
# Integration test (needs Docker): dump a Postgres DB, drop the data, restore, compare.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
cd "$ROOT"
docker compose up -d --wait
docker exec backup-demo-pg psql -U postgres -d shop -c "CREATE TABLE orders(id serial primary key, item text); INSERT INTO orders(item) SELECT 'item-' || g FROM generate_series(1,500) g;"

cat > "$WORK/backup.conf" <<EOF
BACKUP_ROOT=$WORK/backups
PG_DATABASE=shop
PG_USER=postgres
PG_CONTAINER=backup-demo-pg
LOG_FILE=$WORK/backup.log
EOF
export BACKUP_CONFIG="$WORK/backup.conf"

"$ROOT/scripts/backup.sh"
docker exec backup-demo-pg psql -U postgres -d shop -c "DROP TABLE orders;"
"$ROOT/scripts/restore.sh" latest --postgres shop --container backup-demo-pg
count=$(docker exec backup-demo-pg psql -U postgres -d shop -tAc "SELECT count(*) FROM orders;")
test "$count" = "500" || { echo "expected 500 rows, got $count"; exit 1; }
echo "Postgres round-trip OK (500 rows restored)"
docker compose down -v
