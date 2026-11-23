#!/usr/bin/env bash
# Verify a backup set: checksums match and every archive can be read end to end.
#   verify.sh <set-dir>      (default: newest set)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
load_config

SET_DIR="${1:-$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)}"
[[ -d "$SET_DIR" ]] || die "backup set not found: ${SET_DIR}"
[[ -f "$SET_DIR/SHA256SUMS" ]] || die "missing SHA256SUMS in ${SET_DIR}"

( cd "$SET_DIR" && sha256sum --quiet -c SHA256SUMS ) || die "checksum mismatch in ${SET_DIR}"

for f in "$SET_DIR"/*.tar.gz; do
  [[ -e "$f" ]] || continue
  tar -tzf "$f" >/dev/null || die "corrupt archive $f"
done
for f in "$SET_DIR"/*.sql.gz; do
  [[ -e "$f" ]] || continue
  gzip -t "$f" || die "corrupt dump $f"
done
log INFO "verified $(basename "$SET_DIR"): checksums and archives OK"
