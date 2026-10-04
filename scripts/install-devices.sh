#!/usr/bin/env bash
# compila nexo (iphone + reloj + widgets), lo firma con tu equipo y lo instala en tu iphone.
# el reloj recibe su app desde el iphone. con cuenta gratuita el perfil dura 7 dias.
#   TEAM_ID=XXXXXXXXXX ./scripts/install-devices.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TEAM_ID:?define TEAM_ID con tu team id de apple}"
export NEXO_TEAM_ID="$TEAM_ID"
xcodegen generate >/dev/null

tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1
read -r ID UDID < <(python3 - "$tmp" <<'PY'
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    if d.get("hardwareProperties", {}).get("deviceType") == "iPhone" and "available" in d.get("connectionProperties", {}).get("tunnelState", "available") + "available" and d.get("deviceProperties", {}).get("bootState") != "shutdown" and d.get("connectionProperties", {}).get("pairingState") == "paired" and d.get("connectionProperties", {}).get("tunnelState") != "unavailable":
        print(d["identifier"], d["hardwareProperties"].get("udid", "")); break
PY
) || true
[ -n "${ID:-}" ] || { echo "no encontre un iphone conectado" >&2; exit 1; }

xcodebuild -project Nexo.xcodeproj -scheme NexoPhone -configuration Release \
  -destination "platform=iOS,id=$UDID" -allowProvisioningUpdates -derivedDataPath build build | grep -E 'error:|BUILD' || true
APP=$(find build ~/Library/Developer/Xcode/DerivedData/Build/Products -path "*Release-iphoneos/NexoPhone.app" -maxdepth 6 2>/dev/null | head -1)
[ -d "${APP:-}" ] || { echo "no encontre Nexo.app compilado" >&2; exit 1; }
xcrun devicectl device install app --device "$ID" "$APP"
xcrun devicectl device process launch --device "$ID" com.kisnner26.nexo
