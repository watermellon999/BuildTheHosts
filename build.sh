#!/usr/bin/env bash
set -uo pipefail

PROFILE_DIR="${1:?usage: build.sh <profile-dir> <output-file>}"
OUT="${2:?usage: build.sh <profile-dir> <output-file>}"

SOURCES="$PROFILE_DIR/sources.txt"
WHITELIST="$PROFILE_DIR/whitelist.txt"
BLACKLIST="$PROFILE_DIR/blacklist.txt"
HEADERS="$PROFILE_DIR/headers.txt"
LOG="${OUT%.blocked}.log"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() {
  printf "[%s] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2
}

###############################################################################
# fetch(): curl only. No archive, no ETag cache — CI is cold every run.
###############################################################################
fetch() {
  local src="$1" dst="$2"
  if [[ "$src" =~ ^https?:// ]]; then
    local rc=0
    curl -fLsS \
      --retry 3 --retry-delay 2 --retry-connrefused \
      --connect-timeout 15 --max-time 120 \
      --user-agent "hosts-builder/1.0 (+https://github.com)" \
      -o "$dst" "$src" || rc=$?
    if [[ $rc -eq 0 && -s "$dst" ]]; then
      log "OK: fetched $src"
      return 0
    fi
    log "WARN: failed to fetch $src (curl rc=$rc)"
    return 1
  fi
  if cp "$src" "$dst" 2>/dev/null; then
    log "OK: read local file $src"
    return 0
  fi
  log "WARN: failed to read local file $src"
  return 1
}

###############################################################################
# normalize(): strip comments, trim, drop IP prefixes and IP-only lines
###############################################################################
normalize() {
  sed -E '
    s@(//|#).*@@;
    s/^[[:space:]]+//;
    s/[[:space:]]+$//;
    /^$/d;
    s/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+//;
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/d;
    s/\r$//;
  '
}

extract_domains() {
  grep -Eo '([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}' || true
}

> "$TMP/all.domains"

###############################################################################
# Blacklist (highest priority — always included)
###############################################################################
if [[ -f "$BLACKLIST" ]]; then
  log "INFO: loading blacklist"
  normalize < "$BLACKLIST" | extract_domains >> "$TMP/all.domains"
fi

###############################################################################
# Sources
###############################################################################
fetched=0
if [[ -f "$SOURCES" ]]; then
  while read -r src || [[ -n "$src" ]]; do
    [[ -z "$src" || "$src" =~ ^[[:space:]]*(#|//) ]] && continue
    dst="$TMP/src.$fetched"
    if fetch "$src" "$dst"; then
      normalize < "$dst" | extract_domains >> "$TMP/all.domains"
      fetched=$((fetched + 1))
    fi
  done < "$SOURCES"
fi

if [[ "$fetched" -eq 0 && ! -f "$BLACKLIST" ]]; then
  log "ERROR: no sources and no blacklist for profile $PROFILE_DIR"
  exit 1
fi

log "INFO: processed $fetched source(s)"

LC_ALL=C sort -u "$TMP/all.domains" > "$TMP/unique.domains"

###############################################################################
# Whitelist: exact domains + regex: patterns
#   Regex lines are extracted BEFORE normalize/extract so anchors survive.
###############################################################################
if [[ -f "$WHITELIST" ]]; then
  log "INFO: applying whitelist"

  normalize < "$WHITELIST" \
    | grep -v '^regex:' \
    | extract_domains > "$TMP/wl.exact" || true

  grep -E '^[[:space:]]*regex:' "$WHITELIST" \
    | sed -E 's/^[[:space:]]*regex:[[:space:]]*//; s/[[:space:]]+$//; s/\r$//' \
    > "$TMP/wl.regex" || true

  awk -v exactfile="$TMP/wl.exact" -v regexfile="$TMP/wl.regex" '
    BEGIN {
      while ((getline line < exactfile) > 0) if (line != "") exact[line]=1
      close(exactfile)
      r=0
      while ((getline line < regexfile) > 0) if (line != "") regex[++r]=line
      close(regexfile)
    }
    {
      if ($1 in exact) next
      for (i=1;i<=r;i++) if ($1 ~ regex[i]) next
      print $1
    }
  ' "$TMP/unique.domains" > "$TMP/filtered.domains"
else
  cp "$TMP/unique.domains" "$TMP/filtered.domains"
fi

LC_ALL=C sort "$TMP/filtered.domains" > "$TMP/final.domains"

###############################################################################
# Emit hosts file
###############################################################################
{
  [[ -f "$HEADERS" ]] && cat "$HEADERS"
  echo
  echo "# Profile: $PROFILE_DIR"
  echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "# Domains: $(wc -l < "$TMP/final.domains")"
  echo
  while read -r d; do
    printf "0.0.0.0 %s\n" "$d"
  done < "$TMP/final.domains"
} > "$OUT"

log "DONE: $OUT ($(wc -l < "$TMP/final.domains") domains)"
