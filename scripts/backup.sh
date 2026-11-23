#!/usr/bin/env bash
# Create a timestamped backup set: directory archives + optional DB dumps + checksum manifest.
# Then apply retention and (optionally) copy to S3.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config

STAMP="${BACKUP_STAMP:-$(date '+%Y-%m-%d_%H%M%S')}"
SET_DIR="${BACKUP_ROOT}/${STAMP}"
LOCK="${BACKUP_ROOT}/.backup.lock"

mkdir -p "$BACKUP_ROOT"
exec 9>"$LOCK"
flock -n 9 || die "another backup is already running"

log INFO "starting backup set ${STAMP}"
mkdir -p "$SET_DIR"
trap 'log ERROR "backup failed, removing partial set ${SET_DIR}"; rm -rf "$SET_DIR"' ERR

# 1) Directory archives
for src in ${SOURCE_DIRS:-}; do
  if [[ ! -d "$src" ]]; then
    log WARN "skipping missing directory $src"; continue
  fi
  name="$(echo "$src" | sed 's#^/##; s#/#_#g')"
  tar -czf "${SET_DIR}/files_${name}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"
  log INFO "archived $src"
done

# 2) PostgreSQL dump
if [[ -n "${PG_DATABASE:-}" ]]; then
  out="${SET_DIR}/postgres_${PG_DATABASE}.sql.gz"
  if [[ -n "${PG_CONTAINER:-}" ]]; then
    docker exec "$PG_CONTAINER" pg_dump -U "${PG_USER:-postgres}" "$PG_DATABASE" | gzip > "$out"
  else
    pg_dump -h "${PG_HOST:-localhost}" -U "${PG_USER:-postgres}" "$PG_DATABASE" | gzip > "$out"
  fi
  log INFO "dumped postgres database $PG_DATABASE"
fi

# 3) MySQL dump
if [[ -n "${MYSQL_DATABASE:-}" ]]; then
  out="${SET_DIR}/mysql_${MYSQL_DATABASE}.sql.gz"
  if [[ -n "${MYSQL_CONTAINER:-}" ]]; then
    docker exec "$MYSQL_CONTAINER" sh -c "mysqldump --single-transaction -u${MYSQL_USER:-root} -p\"\$MYSQL_ROOT_PASSWORD\" $MYSQL_DATABASE" | gzip > "$out"
  else
    mysqldump --single-transaction -u "${MYSQL_USER:-root}" "$MYSQL_DATABASE" | gzip > "$out"
  fi
  log INFO "dumped mysql database $MYSQL_DATABASE"
fi

shopt -s nullglob
artifacts=("$SET_DIR"/*.gz)
(( ${#artifacts[@]} > 0 )) || die "nothing was backed up (check SOURCE_DIRS / DB settings)"

# 4) Manifest with checksums
(
  cd "$SET_DIR"
  sha256sum -- *.gz > SHA256SUMS
  {
    echo "created=$(date -Iseconds)"
    echo "host=$(hostname)"
    echo "files=$(ls -1 -- *.gz | wc -l)"
    echo "bytes=$(du -cb -- *.gz | tail -1 | cut -f1)"
  } > MANIFEST
)
trap - ERR
log INFO "backup set ${STAMP} complete ($(du -sh "$SET_DIR" | cut -f1))"

# 5) Verify immediately
"$SCRIPT_DIR/verify.sh" "$SET_DIR"

# 6) Retention
"$SCRIPT_DIR/retention.sh"

# 7) Off-site copy
if [[ -n "${S3_BUCKET:-}" ]]; then
  aws s3 sync "$SET_DIR" "s3://${S3_BUCKET}/$(hostname)/${STAMP}/" --only-show-errors
  log INFO "uploaded to s3://${S3_BUCKET}/$(hostname)/${STAMP}/"
fi
echo "$SET_DIR"
