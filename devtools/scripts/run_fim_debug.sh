#!/bin/bash

echo "Compiling TypeFlow..."
xcodebuild -project TypeFlow.xcodeproj -scheme TypeFlow -configuration Debug -clonedSourcePackagesDirPath "$PWD/.xcode-spm" build > stage5l-xcodebuild.log 2>&1
if [ $? -ne 0 ]; then
    echo "Build failed!"
    cat stage5l-xcodebuild.log | grep -i "error:"
    exit 1
fi

echo "Running Qwen 1.5B FIM Debug Mode..."
defaults write com.anshalankarpatil.TypeFlow SalvageMode -integer 0
defaults write com.anshalankarpatil.TypeFlow AfterSpacePromptMode "fim"
defaults write com.anshalankarpatil.TypeFlow FIMEnabled -bool true
defaults write com.anshalankarpatil.TypeFlow TestModelPath -string "/Users/anshalankarpatil/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf"

killall TypeFlow 2>/dev/null || true
rm -f typeflow_live_debug.log

nohup /Users/anshalankarpatil/Library/Developer/Xcode/DerivedData/TypeFlow-cdxlmymoegtqqaewpqvrvvvybrau/Build/Products/Debug/TypeFlow.app/Contents/MacOS/TypeFlow > typeflow_live_debug.log 2>&1 &
sleep 2

osascript <<EOF
    tell application "TextEdit"
        activate
        make new document
    end tell
EOF
sleep 0.5
python3 human_type.py "SELECT * FROM users WHERE "
sleep 2.0
osascript <<EOF
    tell application "System Events"
        key code 53
    end tell
    delay 0.5
    tell application "TextEdit"
        close front document without saving
    end tell
EOF

killall TypeFlow 2>/dev/null || true
echo "Debug Done"
