#!/bin/bash
# SureshJ Photography - photo download (macOS / Linux)
cd "$(dirname "$0")" || exit 1

echo ""
echo "  SureshJ Photography - Photo Download"
echo "  ===================================="
echo ""

fail() { echo ""; echo "  $1"; echo ""; read -r -p "  Press Enter to close "; exit 1; }

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

case "$DESTINATION" in
  [A-Za-z]:\\*|"")
    DESTINATION="$HOME/Downloads/Photos-from-Suresh"
    echo "  No Mac folder set in config.txt, so using:"
    echo "    $DESTINATION"
    echo "  (edit the DESTINATION line in config.txt to change it)"
    echo ""
    ;;
esac
DESTINATION="${DESTINATION/#\~/$HOME}"

echo "  Saving to : $DESTINATION"
echo "  At a time : $TRANSFERS files"
echo ""

RCLONE=""
if [ -x "./rclone" ]; then RCLONE="./rclone"
elif command -v rclone >/dev/null 2>&1; then RCLONE="$(command -v rclone)"
else
  echo "  rclone not found - downloading it (about 20 MB, one time)..."
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
    if [ -n "$BIN" ]; then
      cp "$BIN" ./rclone && chmod +x ./rclone && RCLONE="./rclone"
      echo "  rclone ready."
    fi
  fi
  rm -rf "$TMP"
  [ -n "$RCLONE" ] || fail "Could not download rclone. Install it from https://rclone.org/downloads/ (or: brew install rclone) and run this again."
fi
echo ""

mkdir -p "$DESTINATION" || fail "Cannot create $DESTINATION"
mkdir -p logs

# ---- check there is room BEFORE downloading ----
echo "  Checking how big this job is..."
SIZEURL="${LINK%raw/}size.json"
NEED=$(curl -fsSL --max-time 25 "$SIZEURL" 2>/dev/null | tr -d ' ' | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')
if [ -n "$NEED" ] && [ "$NEED" -gt 0 ]; then
  FREE=$(df -Pk "$DESTINATION" 2>/dev/null | awk 'NR==2{print $4}')
  FREE=$((FREE * 1024))
  NEEDG=$(echo "$NEED" | awk '{printf "%.1f", $1/1073741824}')
  FREEG=$(echo "$FREE" | awk '{printf "%.1f", $1/1073741824}')
  echo "  This job needs ${NEEDG} GB.  That folder has ${FREEG} GB free."
  echo ""
  if [ "$FREE" -lt "$NEED" ]; then
    echo "  ****************************************************"
    echo "   NOT ENOUGH SPACE in $DESTINATION"
    echo "   Needs ${NEEDG} GB, only ${FREEG} GB free."
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

echo "  Downloading... you can stop and re-run this any time, it resumes."
echo ""
"$RCLONE" copy ":http:" "$DESTINATION" --http-url "$LINK" \
  --transfers "$TRANSFERS" --progress --retries 5 --low-level-retries 20 \
  --log-file "logs/download-$STAMP.log" --log-level INFO
COPY_EXIT=$?

echo ""
echo "  Checking every file against the server..."
"$RCLONE" check "$DESTINATION" ":http:" --http-url "$LINK" --size-only \
  --combined verify-result.txt \
  --log-file "logs/verify-$STAMP.log" --log-level INFO
CHECK_EXIT=$?

BAD=0
if [ -f verify-result.txt ]; then BAD="$(grep -cv '^= ' verify-result.txt || true)"; fi
HAVE="$(find "$DESTINATION" -type f | wc -l | tr -d ' ')"

echo ""
echo "  ============================================"
if [ "$COPY_EXIT" -eq 0 ] && [ "$CHECK_EXIT" -eq 0 ] && [ "$BAD" -eq 0 ]; then
  echo "   SUCCESS - all files downloaded and verified."
  echo "   Files on your disk : $HAVE"
  echo "   Folder             : $DESTINATION"
  rm -f verify-result.txt
else
  echo "   NOT FINISHED YET"
  if [ "$BAD" -gt 0 ]; then echo "   $BAD file(s) missing or incomplete."; fi
  echo "   Files on your disk : $HAVE"
  echo ""
  echo "   Just run this again - it will finish the rest."
  echo "   (details: verify-result.txt and the logs folder)"
fi
echo "  ============================================"
echo ""
read -r -p "  Press Enter to close "
