#!/bin/bash

declare -A PROFILES
PROFILES["ProfileA_Baseline"]="-1:0:0:0:0"
PROFILES["ProfileB_DeterministicLowTemp"]="0.1:0:0:0:0"
PROFILES["ProfileC_Greedy"]="0:1:0:0:0"
PROFILES["ProfileD_LowTempAntiRepeat"]="0.1:0:0:1.2:64"
PROFILES["ProfileE_ConstrainedTopK"]="0.2:20:0.9:0:0"

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
xcodebuild -project TypeFlow.xcodeproj -scheme TypeFlow -configuration Debug -clonedSourcePackagesDirPath "$PWD/.xcode-spm" build > stage5g1-xcodebuild.log 2>&1

for profile_name in "ProfileA_Baseline" "ProfileB_DeterministicLowTemp" "ProfileC_Greedy" "ProfileD_LowTempAntiRepeat" "ProfileE_ConstrainedTopK"; do
    profile_settings="${PROFILES[$profile_name]}"
    
    IFS=':' read -r p_temp p_topk p_topp p_repeat p_lastn <<< "$profile_settings"
    
    echo "====================================="
    echo "Testing profile: $profile_name"
    echo "Settings: Temp=$p_temp, TopK=$p_topk, TopP=$p_topp, Repeat=$p_repeat, LastN=$p_lastn"
    echo "====================================="
    
    if [ "$p_temp" == "-1" ]; then
        defaults delete com.anshalankarpatil.TypeFlow TestSamplerTemperature 2>/dev/null || true
    else
        defaults write com.anshalankarpatil.TypeFlow TestSamplerTemperature -float "$p_temp"
    fi
    defaults write com.anshalankarpatil.TypeFlow TestSamplerTopK -int "$p_topk"
    defaults write com.anshalankarpatil.TypeFlow TestSamplerTopP -float "$p_topp"
    defaults write com.anshalankarpatil.TypeFlow TestSamplerRepeatPenalty -float "$p_repeat"
    defaults write com.anshalankarpatil.TypeFlow TestSamplerRepeatLastN -int "$p_lastn"
    
    defaults write com.anshalankarpatil.TypeFlow AfterSpacePromptMode "baseActiveLine"
    
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
    
    cp typeflow_live.log "typeflow_live_$profile_name.log"
    python3 parse_stats_8.py > "stats_$profile_name.txt"
    
    echo "Results for $profile_name:"
    cat "stats_$profile_name.txt"
    echo ""
done

defaults delete com.anshalankarpatil.TypeFlow TestSamplerTemperature 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerTopK 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerTopP 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerRepeatPenalty 2>/dev/null || true
defaults delete com.anshalankarpatil.TypeFlow TestSamplerRepeatLastN 2>/dev/null || true
