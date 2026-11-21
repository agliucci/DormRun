#!/bin/zsh
# Installs a macOS LaunchAgent that scrapes UMass Dining every 3 hours and
# pushes into Supabase when SUPABASE_SERVICE_ROLE_KEY is available.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="ai.getserviceline.runner.menu-scrape"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/DormRun"
mkdir -p "$LOG_DIR"

# Prefer env from a local secrets file (gitignored).
SECRETS="$ROOT/scripts/.scrape.env"
if [[ ! -f "$SECRETS" ]]; then
  cat > "$SECRETS" <<'EOF'
# Fill these, then re-run install_menu_scrape_launchd.sh
export SUPABASE_URL="https://mnlzekxetlbxslxtaluz.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY=""
EOF
  echo "Created $SECRETS — add your service_role key, then re-run this script."
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>source '${SECRETS}' 2>/dev/null; cd '${ROOT}' &amp;&amp; if [[ -n \"\${SUPABASE_SERVICE_ROLE_KEY:-}\" ]]; then /usr/bin/python3 scripts/scrape_umass.py --push; else /usr/bin/python3 scripts/scrape_umass.py; fi</string>
  </array>
  <key>StartInterval</key>
  <integer>10800</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/menu-scrape.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/menu-scrape.err</string>
  <key>WorkingDirectory</key>
  <string>${ROOT}</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/${LABEL}"
echo "Installed ${LABEL} (every 3 hours)."
echo "Secrets: $SECRETS"
echo "Logs:    $LOG_DIR/menu-scrape.log"
