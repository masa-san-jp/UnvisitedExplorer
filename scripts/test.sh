#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="UnvisitedExplorer.xcodeproj"
SCHEME="UnvisitedExplorer"

# シミュレータ名 (iPhone 16 など) を決め打ちすると、ランナーイメージや
# ローカルの Xcode 更新で壊れる。実際に利用可能なデバイスから選ぶ。
# IOS_DESTINATION を渡せば上書きできる。
if [[ -n "${IOS_DESTINATION:-}" ]]; then
  DESTINATION="$IOS_DESTINATION"
else
  UDID="$(xcrun simctl list --json devices available | python3 -c '
import json, re, sys

devices = json.load(sys.stdin)["devices"]
best = None
for runtime, entries in devices.items():
    matched = re.search(r"SimRuntime\.iOS-(\d+)-(\d+)", runtime)
    if not matched:
        continue
    version = (int(matched.group(1)), int(matched.group(2)))
    # デプロイメントターゲットが iOS 17.0。
    if version < (17, 0):
        continue
    for device in entries:
        if not device.get("isAvailable"):
            continue
        if "iPhone" not in device.get("name", ""):
            continue
        if best is None or version > best[0]:
            best = (version, device["udid"], device["name"])

if best is None:
    sys.exit("iOS 17 以降の利用可能な iPhone シミュレータが見つかりません")

print(best[1], file=sys.stdout)
sys.stderr.write("使用するシミュレータ: %s (iOS %d.%d)\n" % (best[2], best[0][0], best[0][1]))
')"
  DESTINATION="id=$UDID"
fi

echo "destination: $DESTINATION"

# CODE_SIGNING_ALLOWED=NO がないと、project.yml の CODE_SIGN_STYLE: Automatic に
# より証明書を要求して CI で落ちる。
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO
