#!/bin/zsh
# Signs and installs Backtalk on a connected iPhone Duo (found by model,
# iPhone19,4, skipping simulators), then launches it.
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate -q
duo=${1:-$(xcrun devicectl list devices -j /dev/stdout 2>/dev/null | python3 -c '
import json, sys
for d in json.load(sys.stdin)["result"]["devices"]:
    h = d.get("hardwareProperties", {})
    if h.get("productType") == "iPhone19,4" and h.get("reality") != "simulated":
        print(h["udid"]); break
')}
if [[ -z "$duo" ]]; then
  echo "No iPhone Duo found. Connected devices:" >&2
  xcrun devicectl list devices >&2
  exit 1
fi
echo "Installing on $duo"
xcodebuild -project Backtalk.xcodeproj -scheme Backtalk -configuration Release \
  -destination "platform=iOS,id=$duo" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -destination-timeout 600 build | grep -E "error:|BUILD"
xcrun devicectl device install app --device "$duo" build/Build/Products/Release-iphoneos/Backtalk.app
xcrun devicectl device process launch --device "$duo" com.bgrayson.backtalk || true
