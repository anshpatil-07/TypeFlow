#!/bin/bash

MODES=(
    "baseActiveLine"
    "cleanProsePreface"
    "fewShotInline"
    "cleanLocalSentence"
    "hybridFewShot"
)

PHRASES=(
    "there is a more pressing matter at hand "
    "the quality of generation is still not good "
    "i want the ghost text to feel natural "
    "this completion should be useful because "
    "we need the suggestion to "
    "the quick brown "
    "ok ill overlook the latency for now "
)

echo "Compiling TypeFlow..."
xcodebuild -project TypeFlow.xcodeproj -scheme TypeFlow -configuration Debug -clonedSourcePackagesDirPath "$PWD/.xcode-spm" build > stage5h2-xcodebuild.log 2>&1

# Ensure sampler overrides are disabled
defaults delete com.anshalankarpatil.TypeFlow TestSamplerTemperature 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerTopK 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerTopP 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerRepeatPenalty 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerRepeatLastN 2>/dev/null || true

for mode_name in "${MODES[@]}"; do
    echo "====================================="
    echo "Testing Prompt Mode: $mode_name"
    echo "====================================="
    
    defaults write com.anshalankarpatil.TypeFlow AfterSpacePromptMode "$mode_name"
    
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
    
    cp typeflow_live.log "typeflow_live_$mode_name.log"
    python3 parse_stats_8.py > "stats_$mode_name.txt"
    
    echo "Results for $mode_name:"
    cat "stats_$mode_name.txt"
    echo ""
done

# Reset to baseline
defaults write com.anshalankarpatil.TypeFlow AfterSpacePromptMode "baseActiveLine"
