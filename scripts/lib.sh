#!/usr/bin/env bash
# Shared helpers for backup scripts.

# Variables set here are consumed by the scripts that source this file.
# shellcheck disable=SC2034
load_config() {
  local cfg="${BACKUP_CONFIG:-}"
  if [[ -z "$cfg" ]]; then
    for c in ./config/backup.conf /etc/backup.conf; do
      [[ -f "$c" ]] && cfg="$c" && break
    done
  fi
  if [[ -n "$cfg" ]]; then
    # shellcheck disable=SC1090
    source "$cfg"
  fi
  BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/app}"
  KEEP_DAILY="${KEEP_DAILY:-7}"
  KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
  LOG_FILE="${LOG_FILE:-/var/log/backup.log}"
}

log() {
  local level="$1"; shift
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
  echo "$line" >&2
  echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}

die() { log ERROR "$*"; exit 1; }

sha256_of() { sha256sum "$1" | awk '{print $1}'; }
