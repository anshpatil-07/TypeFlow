import sys
import re
from collections import Counter

def analyze(path):
    print(f"Analyzing {path}...")
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except Exception as e:
        print(e)
        return

    counts = Counter()
    apps = Counter()
    
    for line in lines:
        lower = line.lower()
        if "tap=observer eventtype=keydown" in lower: counts['keyDown'] += 1
        if "tap=observer eventtype=keyup" in lower: counts['keyUp'] += 1
        
        # focusedPID / app
        pid_match = re.search(r"focusedPID=(\d+)", line, re.IGNORECASE)
        app_match = re.search(r"focusedApp=([^ ]+)", line, re.IGNORECASE)
        if pid_match: counts['focusedPID_logs'] += 1
        if app_match: apps[app_match.group(1)] += 1
        
        if "swallowed=true" in lower: counts['swallowed=true'] += 1
        if "originalreturned=false" in lower: counts['originalReturned=false'] += 1
        
        if "axvaluechanged" in lower or "value changed" in lower or "kaxvaluechanged" in lower or "axobserver" in lower and "value" in lower: counts['AXValueChanged'] += 1
        if "ontextchanged" in lower: counts['onTextChanged'] += 1
        if "result ownership advanced" in lower and "stage1a" in lower: counts['Stage1A ownership advanced'] += 1
        
        if "[debounceaudit]" in lower and "textchanged received" in lower: counts['Debounce textChanged received'] += 1
        if "[debounceaudit]" in lower and "scheduled" in lower: counts['Debounce scheduled'] += 1
        if "[debounceaudit]" in lower and "fired" in lower: counts['Debounce fired'] += 1
        
        if "triggergeneration started" in lower or "triggergeneration" in lower and "start" in lower: counts['triggerGeneration started'] += 1
        if "gettextbeforecaret start" in lower or ("gettextbeforecaret" in lower and "start" in lower): counts['getTextBeforeCaret start'] += 1
        if "ax kaxvalue" in lower or "kaxvalue" in lower: counts['AX kAXValue'] += 1
        if "context canonicalization audit" in lower or "canonicalization" in lower: counts['Context Canonicalization Audit'] += 1
        
        if "llmengine" in lower and "generatecompletion" in lower: counts['generateCompletion called'] += 1
        if "[stage1b]" in lower and "generation started" in lower: counts['Stage1B generation started'] += 1
        if "raw model output" in lower: counts['Raw model output'] += 1
        if "processed completion" in lower or "processedoutput=" in lower: counts['Processed completion'] += 1
        if "[qualityaudit]" in lower: counts['QualityAudit'] += 1
        
        if "render attempt" in lower and "stage1a" in lower:
            if "allowed" in lower: counts['Stage1A render ALLOWED'] += 1
            if "blocked" in lower: counts['Stage1A render BLOCKED'] += 1
            
        if "[renderpipeline]" in lower:
            if "render requested" in lower or "requested" in lower: counts['Render requested'] += 1
            if "render applied" in lower or "applied" in lower: counts['Render applied'] += 1
        
        if "overlaywindowevent=orderfront" in lower: counts['overlayWindowEvent=orderFront'] += 1
        if "layercountafter" in lower:
            val = re.search(r"layerCountAfter=(\d+)", line)
            if val and int(val.group(1)) > 1: counts['overlay layerCountAfter > 1'] += 1

    print("=== METRICS ===")
    for k, v in counts.items():
        print(f"{k}: {v}")
        
    print("\n=== APPS ===")
    for k, v in apps.items():
        print(f"{k}: {v}")

if __name__ == "__main__":
    analyze(sys.argv[1])
