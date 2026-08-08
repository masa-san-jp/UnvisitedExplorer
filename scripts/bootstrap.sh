#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGenが必要です。Homebrewでインストールします。"
  brew install xcodegen
fi

cd "$(dirname "$0")/.."

# project.yml が ${DEVELOPMENT_TEAM} を参照する。未設定でも展開できるよう空で定義する。
export DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
if [ -z "$DEVELOPMENT_TEAM" ]; then
  echo "注意: DEVELOPMENT_TEAM が未設定です。実機ビルドには署名チームが必要です。"
  echo "      Team ID は次で確認できます: security find-identity -v -p codesigning"
  echo "      設定例: export DEVELOPMENT_TEAM=XXXXXXXXXX"
fi

xcodegen generate
