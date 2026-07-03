#!/bin/bash

PHRASES=(
    "there is a more pressing matter at hand "
    "the quality of generation is still not good "
    "i want the ghost text to feel natural "
    "this completion should be useful because "
    "we need the suggestion to "
    "the quick brown "
    "ok ill overlook the latency for now "
    "public ResponseEntity<User> getUserById("
    "SELECT * FROM users WHERE "
)

echo "Compiling TypeFlow..."
xcodebuild -project TypeFlow.xcodeproj -scheme TypeFlow -configuration Debug -clonedSourcePackagesDirPath "$PWD/.xcode-spm" build > stage5k0-xcodebuild.log 2>&1

echo "Running Qwen 1.5B Baseline (No Salvage)..."
defaults write com.anshalankarpatil.TypeFlow SalvageMode -integer 0
defaults write com.anshalankarpatil.TypeFlow AfterSpacePromptMode "baseActiveLine"
defaults write com.anshalankarpatil.TypeFlow TestModelPath -string "/Users/anshalankarpatil/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf"

killall TypeFlow 2>/dev/null || true
rm -f typeflow_live.log

nohup /Users/anshalankarpatil/Library/Developer/Xcode/DerivedData/TypeFlow-cdxlmymoegtqqaewpqvrvvvybrau/Build/Products/Debug/TypeFlow.app/Contents/MacOS/TypeFlow > typeflow_live.log 2>&1 &
sleep 3

for phrase in "${PHRASES[@]}"; do
    osascript <<EOF
        tell application "TextEdit"
            activate
            make new document
        end tell
EOF
    sleep 0.5
    python3 human_type.py "$phrase"
    sleep 1.2
    osascript <<EOF
        tell application "System Events"
            key code 53
        end tell
        delay 0.5
        tell application "TextEdit"
            close front document without saving
        end tell
EOF
    sleep 1
done

killall TypeFlow 2>/dev/null || true
python3 parse_stats_8.py > "stats_qwen_1_5B.txt"

echo "Done"
