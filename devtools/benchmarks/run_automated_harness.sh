#!/bin/bash
MODES=("baseActiveLine" "baseActiveLineWithMinimalComment" "suffixOnlyBase" "disabledInstructionWrapper")
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
xcodebuild -project TypeFlow.xcodeproj -scheme TypeFlow -configuration Debug -clonedSourcePackagesDirPath "$PWD/.xcode-spm" build > stage5f2-xcodebuild.log 2>&1

for mode in "${MODES[@]}"; do
    echo "====================================="
    echo "Testing mode: $mode"
    echo "====================================="
    
    defaults write com.anshalankarpatil.TypeFlow AfterSpacePromptMode "$mode"
    
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
        
        # Pause at the end to allow for TypeFlow generation
        sleep 1.2
        
        osascript <<EOF
            tell application "System Events"
                key code 53 -- Escape to clear ghost text
            end tell
            delay 0.5
            tell application "TextEdit"
                close front document without saving
            end tell
EOF
        sleep 1
    done
    
    killall TypeFlow 2>/dev/null || true
    
    cp typeflow_live.log "typeflow_live_$mode.log"
    python3 .agents/skills/typeflow-log-auditor/scripts/audit_typeflow_log.py typeflow_live.log > "audit_report_$mode.txt"
    python3 parse_stats_8.py > "stats_$mode.txt"
    
    echo "Results for $mode:"
    cat "stats_$mode.txt"
    echo ""
done
