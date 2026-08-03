#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGenが必要です。Homebrewでインストールします。"
  brew install xcodegen
fi

cd "$(dirname "$0")/.."
xcodegen generate
