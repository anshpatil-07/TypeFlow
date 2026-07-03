#!/bin/bash

echo "Starting Stress Harness..."

killall TypeFlow 2>/dev/null || true
rm -f typeflow_stress.log

nohup /Users/anshalankarpatil/Library/Developer/Xcode/DerivedData/TypeFlow-cdxlmymoegtqqaewpqvrvvvybrau/Build/Products/Debug/TypeFlow.app/Contents/MacOS/TypeFlow \
    -modelPath "/Users/anshalankarpatil/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf" \
    -modelProfileID "qwenCoderFIM" \
    -SalvageMode 0 \
    -AfterSpacePromptMode "fim" \
    > typeflow_stress.log 2>&1 &
sleep 3

run_test() {
    name=$1
    wpm=$2
    backspace=$3
    text=$4
    
    echo "Running stress test: $name"
    osascript -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document'
    sleep 0.5
    python3 stress_type.py --wpm "$wpm" --backspace "$backspace" --text "$text "
    sleep 1.2
    osascript -e 'tell application "System Events" to key code 53'
    sleep 0.5
    osascript -e 'tell application "TextEdit" to close front document without saving'
    sleep 1
}

run_test "Normal WPM" 140 0.0 "The quick brown fox jumps over the lazy dog"
run_test "Burst WPM" 220 0.0 "It was the best of times, it was the worst of times"
run_test "Backspacing" 140 0.2 "This sentence has a lot of typos that I will fix"
run_test "Short phrases" 150 0.0 "Hello world"
run_test "Code phrases" 180 0.0 "function calculateTotal(price, taxRate) { return price * (1 + taxRate); }"
run_test "Long paragraph" 150 0.0 "TypeFlow is a system-wide AI autocomplete macOS menu bar app that works in every Mac application. It monitors the active text field using Accessibility APIs and injects ghost-text completions inline, powered by a local LLM running entirely on-device via Apple's MLX framework. It provides contextual completions by combining active text, surrounding screen text via Vision OCR, and clipboard contents."

killall TypeFlow 2>/dev/null || true
echo "Stress test done."
