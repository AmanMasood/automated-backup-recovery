#!/usr/bin/env bash
# Restore from a backup set.
#   restore.sh --list
#   restore.sh <set-name|latest> --target /restore/path [--dry-run]
#   restore.sh <set-name|latest> --postgres <database> [--container pg]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config

if [[ "${1:-}" == "--list" ]]; then
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' | sort -r | while read -r s; do
    printf '%s  %s\n' "$s" "$(du -sh "$BACKUP_ROOT/$s" | cut -f1)"
  done
  exit 0
fi

SET="${1:?usage: restore.sh <set|latest> --target DIR | --postgres DB}"; shift
if [[ "$SET" == "latest" ]]; then
  SET="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' | sort | tail -1)"
fi
SET_DIR="$BACKUP_ROOT/$SET"
TARGET="" PG_DB="" CONTAINER="" DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --postgres) PG_DB="$2"; shift 2 ;;
    --container) CONTAINER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) die "unknown option $1" ;;
  esac
done

"$SCRIPT_DIR/verify.sh" "$SET_DIR"   # never restore an unverified set

if [[ -n "$TARGET" ]]; then
  mkdir -p "$TARGET"
  for f in "$SET_DIR"/files_*.tar.gz; do
    [[ -e "$f" ]] || continue
    if (( DRY_RUN )); then
      log INFO "[dry-run] would extract $(basename "$f") into $TARGET ($(tar -tzf "$f" | wc -l) entries)"
    else
      tar -xzf "$f" -C "$TARGET"
      log INFO "restored $(basename "$f") into $TARGET"
    fi
  done
fi

if [[ -n "$PG_DB" ]]; then
  dump=$(ls "$SET_DIR"/postgres_*.sql.gz | head -1)
  if (( DRY_RUN )); then
    log INFO "[dry-run] would load $(basename "$dump") into postgres database $PG_DB"
  elif [[ -n "$CONTAINER" ]]; then
    gunzip -c "$dump" | docker exec -i "$CONTAINER" psql -q -U "${PG_USER:-postgres}" "$PG_DB"
  else
    gunzip -c "$dump" | psql -q -h "${PG_HOST:-localhost}" -U "${PG_USER:-postgres}" "$PG_DB"
  fi
  log INFO "restored postgres database $PG_DB from $SET"
fi
log INFO "restore of $SET finished"
