#!/bin/bash
# SureshJ Photography - download (macOS / Linux)
# 21 Sep 2026: checks the link first (expired / offline said plainly), fetches the
# LIVE file list from the server every run, says what you already have and what
# is left, checks free space against what is LEFT, and tells Suresh on success.
cd "$(dirname "$0")" || exit 1

echo ""
echo "  SureshJ Photography - Download"
echo "  =============================="
echo ""

fail() { echo ""; echo "  $1"; echo ""; read -r -p "  Press Enter to close "; exit 1; }
gb() { echo "$1" | awk '{printf "%.1f", $1/1073741824}'; }

[ -f config.txt ] || fail "ERROR: config.txt not found next to this file."

DESTINATION=""; LINK=""; TRANSFERS=""
while IFS= read -r raw || [ -n "$raw" ]; do
  line="${raw%$'\r'}"
  case "$line" in ''|'#'*) continue ;; esac
  key="${line%%=*}"; val="${line#*=}"
  key="$(echo "$key" | tr -d ' ' | tr '[:lower:]' '[:upper:]')"
  case "$key" in
    DESTINATION) DESTINATION="$val" ;;
    LINK)        LINK="$val" ;;
    TRANSFERS)   TRANSFERS="$val" ;;
  esac
done < config.txt

[ -n "$LINK" ] || fail "ERROR: config.txt is missing the LINK line."
[ -n "$TRANSFERS" ] || TRANSFERS=4
case "$LINK" in */) ;; *) LINK="$LINK/" ;; esac
BASE="${LINK%raw/}"

case "$DESTINATION" in
  [A-Za-z]:\\*|"")
    DESTINATION="$HOME/Downloads/Photos-from-Suresh"
    echo "  No Mac folder set in config.txt, so using:"
    echo "    $DESTINATION"
    echo ""
    ;;
esac
DESTINATION="${DESTINATION/#\~/$HOME}"

# ---- 1. is the link alive? ----
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$LINK")
case "$CODE" in
  200) ;;
  410) fail "YOUR LINK HAS EXPIRED.
  Nothing is wrong with your computer. Please message Suresh -
  he can reopen it, and then you just run this again."
    ;;
  000) fail "CANNOT REACH THE SERVER - check your internet, then run this again." ;;
  *)   fail "THE SERVER SAID NO (code $CODE). Please message Suresh." ;;
esac

echo "  Saving to : $DESTINATION"
echo ""

RCLONE=""
if [ -x "./rclone" ]; then RCLONE="./rclone"
elif command -v rclone >/dev/null 2>&1; then RCLONE="$(command -v rclone)"
else
  echo "  Getting the download helper (about 20 MB, one time)..."
  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in
    Darwin) case "$ARCH" in arm64) PKG="osx-arm64" ;; *) PKG="osx-amd64" ;; esac ;;
    Linux)  case "$ARCH" in aarch64|arm64) PKG="linux-arm64" ;; *) PKG="linux-amd64" ;; esac ;;
    *) fail "Unsupported system: $OS" ;;
  esac
  TMP="$(mktemp -d)"
  if curl -fsSL "https://downloads.rclone.org/rclone-current-${PKG}.zip" -o "$TMP/rclone.zip" \
     && unzip -q -o "$TMP/rclone.zip" -d "$TMP"; then
    BIN="$(find "$TMP" -type f -name rclone | head -n 1)"
    if [ -n "$BIN" ]; then cp "$BIN" ./rclone && chmod +x ./rclone && RCLONE="./rclone"; fi
  fi
  rm -rf "$TMP"
  [ -n "$RCLONE" ] || fail "Could not download rclone. Install it from https://rclone.org/downloads/ (or: brew install rclone) and run this again."
  echo "  Ready."
  echo ""
fi

mkdir -p "$DESTINATION" || fail "Cannot create $DESTINATION"
mkdir -p logs

# ---- 2. what does the job contain, and what do you already have? ----
echo "  Comparing your folder with Suresh's list..."
LIVE="logs/manifest-live.txt"
HAVE_N=0; HAVE_B=0; LEFT_N=0; LEFT_B=0; WANT_N=0; WANT_B=0
if curl -fsS --max-time 60 "${BASE}manifest.txt" -o "$LIVE" 2>/dev/null && grep -q '^# Files:' "$LIVE"; then
  cp "$LIVE" MANIFEST.txt                      # VERIFY always checks the current list
  WANT_N=$(sed -n 's/^# Files: //p' "$LIVE" | head -1)
  WANT_B=$(sed -n 's/^# Bytes: //p' "$LIVE" | head -1)
  while IFS=$'\t' read -r size path; do
    case "$size" in \#*|'') continue ;; esac
    f="$DESTINATION/$path"
    if [ -f "$f" ] && [ "$(wc -c < "$f" | tr -d ' ')" = "$size" ]; then
      HAVE_N=$((HAVE_N+1)); HAVE_B=$((HAVE_B+size))
    else
      LEFT_N=$((LEFT_N+1)); LEFT_B=$((LEFT_B+size))
    fi
  done < "$LIVE"
  echo ""
  echo "  This job      : $WANT_N files, $(gb "$WANT_B") GB"
  echo "  You have      : $HAVE_N files, $(gb "$HAVE_B") GB"
  echo "  Still to get  : $LEFT_N files, $(gb "$LEFT_B") GB"
  echo ""
  NEED=$LEFT_B
else
  NEED=$(curl -fsSL --max-time 25 "${BASE}size.json" 2>/dev/null | tr -d ' ' | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
  LEFT_N=1
fi

# ---- 3. room for what is left? ----
if [ -n "$NEED" ] && [ "$NEED" -gt 0 ]; then
  FREE=$(df -Pk "$DESTINATION" 2>/dev/null | awk 'NR==2{print $4}')
  FREE=$((FREE * 1024))
  if [ "$FREE" -lt "$NEED" ]; then
    echo "  ****************************************************"
    echo "   NOT ENOUGH SPACE in $DESTINATION"
    echo "   Needs $(gb "$NEED") GB more, only $(gb "$FREE") GB free."
    echo "  ****************************************************"
    echo ""
    if [ -d /Volumes ]; then
      echo "  Drives connected to this Mac, and their free space:"
      for v in /Volumes/*; do
        [ -d "$v" ] || continue
        f=$(df -Pk "$v" 2>/dev/null | awk 'NR==2{print $4}')
        [ -n "$f" ] || continue
        g=$(echo "$f" | awk '{printf "%.0f", $1/1048576}')
        if [ "$((f * 1024))" -ge "$NEED" ]; then mark="  <-- this one fits"; else mark=""; fi
        printf "    %-38s %6s GB free%s\n" "$v" "$g" "$mark"
      done
      echo ""
      echo "  To use one of those, open config.txt and set for example:"
      echo "    DESTINATION=/Volumes/YourDrive/Jobs"
      echo ""
    fi
    printf "  Continue anyway? (y/n) "
    read -r ANSWER
    case "$ANSWER" in [Yy]*) ;; *) echo ""; echo "  Stopped. Nothing downloaded."; echo ""; read -r -p "  Press Enter to close "; exit 0 ;; esac
    echo ""
  fi
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
COPY_EXIT=0
if [ "$LEFT_N" -gt 0 ]; then
  echo "  Downloading... you can stop and re-run this any time - it carries on"
  echo "  from where it stopped. (The totals below count only what is left.)"
  echo ""
  "$RCLONE" copy ":http:" "$DESTINATION" --http-url "$LINK" \
    --transfers "$TRANSFERS" --progress --retries 5 --low-level-retries 20 \
    --log-file "logs/download-$STAMP.log" --log-level INFO
  COPY_EXIT=$?
else
  echo "  You already have everything - just double-checking."
fi

# ---- 4. check every file against the server (extra files of yours are fine) ----
echo ""
echo "  Checking every file against the server..."
rm -f verify-result.txt
"$RCLONE" check ":http:" "$DESTINATION" --http-url "$LINK" --size-only --one-way \
  --combined verify-result.txt \
  --log-file "logs/verify-$STAMP.log" --log-level INFO
CHECK_EXIT=$?

BAD=0
if [ -f verify-result.txt ]; then BAD="$(grep -c '^[-*!]' verify-result.txt || true)"; fi

# gone mid-run? say so plainly rather than "run again"
CODE2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$LINK")

echo ""
echo "  ============================================"
if [ "$COPY_EXIT" -eq 0 ] && [ "$CHECK_EXIT" -eq 0 ] && [ "$BAD" -eq 0 ]; then
  echo "   SUCCESS - all files downloaded and verified."
  [ "$WANT_N" -gt 0 ] && echo "   Files : $WANT_N  ($(gb "$WANT_B") GB)"
  echo "   Folder: $DESTINATION"
  rm -f verify-result.txt
  BODY="{\"complete\":true,\"files\":$WANT_N,\"bytes\":$WANT_B,\"expectedFiles\":$WANT_N,\"expectedBytes\":$WANT_B,\"missing\":0,\"wrongSize\":0,\"folder\":\"$DESTINATION\"}"
  if curl -fsS --max-time 20 -X POST -H "Content-Type: application/json" -d "$BODY" "${BASE}confirm" >/dev/null 2>&1; then
    echo ""
    echo "   Suresh has been told automatically. Nothing else to do."
  fi
elif [ "$CODE2" = "410" ]; then
  echo "   YOUR LINK EXPIRED while downloading."
  echo "   Please message Suresh - he can reopen it, then run this again."
  echo "   Everything you already have is kept."
else
  echo "   NOT FINISHED YET"
  [ "$BAD" -gt 0 ] && echo "   $BAD file(s) still missing or incomplete."
  echo ""
  echo "   Run this again - it carries on from where it stopped."
  echo "   If it keeps saying this, send Suresh the file verify-result.txt"
fi
echo "  ============================================"
echo ""
read -r -p "  Press Enter to close "
