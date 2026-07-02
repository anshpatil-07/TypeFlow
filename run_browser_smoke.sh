#!/bin/bash

echo "Starting Browser Smoke Test..."

killall TypeFlow 2>/dev/null || true
rm -f typeflow_browser.log

nohup /Users/anshalankarpatil/Library/Developer/Xcode/DerivedData/TypeFlow-cdxlmymoegtqqaewpqvrvvvybrau/Build/Products/Debug/TypeFlow.app/Contents/MacOS/TypeFlow \
    -modelPath "/Users/anshalankarpatil/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf" \
    -modelProfileID "qwenCoderFIM" \
    -SalvageMode 0 \
    -AfterSpacePromptMode "fim" \
    > typeflow_browser.log 2>&1 &
sleep 3

python3 browser_smoke.py

killall TypeFlow 2>/dev/null || true
echo "Browser Smoke test done."
