#!/usr/bin/env bash
# compila el hub de nexo y lo instala en /Applications. despues abrelo: aparece en la barra de menus.
#   ./scripts/install-mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "falta xcodegen: brew install xcodegen" >&2; exit 1; }
xcodegen generate >/dev/null
xcodebuild -project Nexo.xcodeproj -scheme NexoMac -configuration Release -derivedDataPath build CONFIGURATION_BUILD_DIR="$PWD/build/out" \
  CODE_SIGNING_ALLOWED=NO build | grep -E 'error:|BUILD' || true
# identidad estable: los permisos de accesibilidad sobreviven a cada actualizacion
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --deep --sign "${IDENTITY:--}" build/out/NexoMac.app
pkill -x NexoMac 2>/dev/null || true
rm -rf /Applications/Nexo.app
cp -R build/out/NexoMac.app /Applications/Nexo.app
open /Applications/Nexo.app
