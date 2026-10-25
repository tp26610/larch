#!/bin/bash
# 煙霧測試：驅動真實視窗與 WKWebView（會開視窗）。失敗時 exit code 非 0。
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
"$(swift build --show-bin-path)/MyBrowser" --smoke
