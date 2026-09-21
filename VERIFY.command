#!/bin/bash
# SureshJ Photography - check your files against Suresh's list
# 21 Sep 2026: checks against the LIVE list on the server (it can change after
# you got the zip); falls back to the MANIFEST.txt in the zip if offline.
cd "$(dirname "$0")" || exit 1

echo ""
echo "  Checking your files against Suresh's list"
echo "  ========================================"
echo ""

fail() { echo ""; echo "  $1"; echo ""; read -r -p "  Press Enter to close "; exit 1; }
gb() { echo "$1" | awk '{printf "%.1f", $1/1073741824}'; }

DESTINATION=""; LINK=""
if [ -f config.txt ]; then
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    key="$(echo "${line%%=*}" | tr -d ' ' | tr '[:lower:]' '[:upper:]')"
    case "$key" in
      DESTINATION) DESTINATION="${line#*=}" ;;
      LINK)        LINK="${line#*=}" ;;
    esac
  done < config.txt
fi
case "$DESTINATION" in [A-Za-z]:\\*|"") DESTINATION="" ;; esac
DESTINATION="${DESTINATION/#\~/$HOME}"

SOURCE="the list in your zip"
if [ -n "$LINK" ]; then
  case "$LINK" in */) ;; *) LINK="$LINK/" ;; esac
  CODE=$(curl -s -o MANIFEST.live -w '%{http_code}' --max-time 60 "${LINK%raw/}manifest.txt")
  if [ "$CODE" = "200" ] && grep -q '^# Files:' MANIFEST.live; then
    mv -f MANIFEST.live MANIFEST.txt; SOURCE="Suresh's current list"
  else
    rm -f MANIFEST.live
    [ "$CODE" = "410" ] && echo "  (Your link has expired - checking against the list in your zip.)" && echo ""
  fi
fi
[ -f MANIFEST.txt ] || fail "ERROR: MANIFEST.txt is not next to this file."

if [ -z "$DESTINATION" ] || [ ! -d "$DESTINATION" ]; then
  echo "  Which folder are the files in?"
  echo "  (drag the folder into this window, then press Enter)"
  printf "  Folder: "
  read -r DESTINATION
  DESTINATION="$(echo "$DESTINATION" | sed "s/^['\"]//;s/['\"]$//")"
  DESTINATION="${DESTINATION/#\~/$HOME}"
fi
[ -d "$DESTINATION" ] || fail "That folder does not exist: $DESTINATION"

JOB=$(sed -n 's/^# Job: //p' MANIFEST.txt | head -1)
WANT_N=$(sed -n 's/^# Files: //p' MANIFEST.txt | head -1)
WANT_B=$(sed -n 's/^# Bytes: //p' MANIFEST.txt | head -1)

echo "  Job     : $JOB"
echo "  Folder  : $DESTINATION"
echo "  Against : $SOURCE"
echo ""
echo "  Reading your files..."

TMP="$(mktemp -d)"
MISSING="$TMP/missing"; WRONG="$TMP/wrong"
: > "$MISSING"; : > "$WRONG"

HAVE_N=0; HAVE_B=0
while IFS=$'\t' read -r size path; do
  size="${size%$'\r'}"; path="${path%$'\r'}"
  case "$size" in \#*|'') continue ;; esac
  f="$DESTINATION/$path"
  if [ ! -f "$f" ]; then
    echo "$path" >> "$MISSING"
  else
    actual=$(wc -c < "$f" | tr -d ' ')
    if [ "$actual" != "$size" ]; then
      echo "$path (expected $size bytes, has $actual)" >> "$WRONG"
    else
      HAVE_N=$((HAVE_N+1)); HAVE_B=$((HAVE_B+actual))
    fi
  fi
done < MANIFEST.txt

MISS_N=$(wc -l < "$MISSING" | tr -d ' ')
WRONG_N=$(wc -l < "$WRONG" | tr -d ' ')

{
  echo "RESULT - SureshJ Photography"
  echo "Job     : $JOB"
  echo "Folder  : $DESTINATION"
  echo "Checked : $(date '+%Y-%m-%d %H:%M')  against $SOURCE"
  echo ""
  echo "Suresh sent : $WANT_N files   $(gb "$WANT_B") GB"
  echo "You have    : $HAVE_N files   $(gb "$HAVE_B") GB"
  echo ""
  if [ "$MISS_N" -eq 0 ] && [ "$WRONG_N" -eq 0 ]; then
    echo "COMPLETE - every file is present and the right size."
  else
    echo "NOT COMPLETE - run DOWNLOAD again, it carries on from where it stopped."
    [ "$MISS_N" -gt 0 ]  && echo "  $MISS_N file(s) missing"
    [ "$WRONG_N" -gt 0 ] && echo "  $WRONG_N file(s) the wrong size (download did not finish)"
    echo ""
    if [ "$MISS_N" -gt 0 ]; then
      echo "MISSING FILES:"; head -200 "$MISSING"
      [ "$MISS_N" -gt 200 ] && echo "  ...and $((MISS_N-200)) more"
    fi
    if [ "$WRONG_N" -gt 0 ]; then
      echo ""; echo "WRONG SIZE:"; head -100 "$WRONG"
    fi
  fi
} > RESULT.txt

sed 's/^/  /' RESULT.txt
rm -rf "$TMP"

# tell Suresh automatically (best effort - RESULT.txt is still the fallback)
if [ -n "$LINK" ]; then
  if [ "$MISS_N" -eq 0 ] && [ "$WRONG_N" -eq 0 ]; then CFLAG=true; else CFLAG=false; fi
  BODY="{\"complete\":$CFLAG,\"files\":$HAVE_N,\"bytes\":$HAVE_B,\"expectedFiles\":$WANT_N,\"expectedBytes\":$WANT_B,\"missing\":$MISS_N,\"wrongSize\":$WRONG_N,\"folder\":\"$DESTINATION\"}"
  if curl -fsS --max-time 20 -X POST -H "Content-Type: application/json" -d "$BODY" "${LINK%raw/}confirm" >/dev/null 2>&1; then
    SENT=1
  fi
fi
echo ""
echo "  ============================================"
if [ "${SENT:-0}" = "1" ]; then
  echo "   Done. Suresh already has this result."
else
  echo "   A file called RESULT.txt is now in this folder."
  echo "   Please send RESULT.txt to Suresh."
fi
echo "  ============================================"
echo ""
read -r -p "  Press Enter to close "
