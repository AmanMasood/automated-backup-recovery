#!/usr/bin/env bash
# Keep the newest KEEP_DAILY sets, plus the newest KEEP_WEEKLY sets taken on a Sunday.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config

mapfile -t sets < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' | sort -r)
declare -A keep=()

for s in "${sets[@]:0:$KEEP_DAILY}"; do keep["$s"]=1; done

weekly=0
for s in "${sets[@]}"; do
  (( weekly >= KEEP_WEEKLY )) && break
  day="${s%%_*}"
  if [[ "$(date -d "$day" +%u 2>/dev/null)" == "7" ]]; then
    keep["$s"]=1; weekly=$((weekly + 1))
  fi
done

removed=0
for s in "${sets[@]}"; do
  if [[ -z "${keep[$s]:-}" ]]; then
    rm -rf "${BACKUP_ROOT:?}/$s"; removed=$((removed + 1))
    log INFO "retention: removed $s"
  fi
done
log INFO "retention: kept ${#keep[@]} set(s), removed ${removed}"
