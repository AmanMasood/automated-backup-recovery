#!/usr/bin/env bash
# End-to-end test: backup -> verify -> corrupt detection -> retention -> restore.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/src/site" "$WORK/src/config"
echo "<h1>hello</h1>" > "$WORK/src/site/index.html"
echo "setting=1" > "$WORK/src/config/app.ini"

cat > "$WORK/backup.conf" <<EOF
BACKUP_ROOT=$WORK/backups
SOURCE_DIRS="$WORK/src/site $WORK/src/config $WORK/does-not-exist"
KEEP_DAILY=3
KEEP_WEEKLY=1
LOG_FILE=$WORK/backup.log
EOF
export BACKUP_CONFIG="$WORK/backup.conf"

echo "1) create a backup"
SET=$("$ROOT/scripts/backup.sh")
test -f "$SET/SHA256SUMS" && test -f "$SET/MANIFEST"
test "$(ls "$SET"/*.tar.gz | wc -l)" -eq 2
grep -q "skipping missing directory" "$WORK/backup.log"

echo "2) verify passes"
"$ROOT/scripts/verify.sh" "$SET"

echo "3) corruption is detected"
cp -r "$SET" "$WORK/corrupt"
echo garbage >> "$(ls "$WORK"/corrupt/*.tar.gz | head -1)"
if "$ROOT/scripts/verify.sh" "$WORK/corrupt" 2>/dev/null; then echo "corruption not detected"; exit 1; fi

echo "4) retention keeps 3 daily + 1 weekly (Sunday)"
for d in 2026-01-04 2026-01-05 2026-01-06 2026-01-07 2026-01-08 2026-01-11 2026-01-12; do
  BACKUP_STAMP="${d}_020000" "$ROOT/scripts/backup.sh" >/dev/null
done
remaining=$(find "$WORK/backups" -mindepth 1 -maxdepth 1 -type d -name '20*' | wc -l)
# newest 3 by name = today's set + 2026-01-12 + 2026-01-11 (Sunday, counts as the weekly too)
test "$remaining" -eq 3 || { echo "expected 3 sets, got $remaining"; ls "$WORK/backups"; exit 1; }
test -d "$WORK/backups/2026-01-11_020000"
test ! -d "$WORK/backups/2026-01-04_020000"

echo "5) restore latest into a new directory"
"$ROOT/scripts/restore.sh" latest --target "$WORK/restored" --dry-run
"$ROOT/scripts/restore.sh" latest --target "$WORK/restored"
diff "$WORK/src/site/index.html" "$WORK/restored/site/index.html"
diff "$WORK/src/config/app.ini" "$WORK/restored/config/app.ini"

echo "6) report tool"
python3 "$ROOT/scripts/backup_report.py" --root "$WORK/backups" --max-age-hours 1
"$ROOT/scripts/restore.sh" --list

echo "All backup/recovery tests passed"
