import re
import sys

def parse_logs(log_file):
    pb_afterSpace = 0
    pb_midWord = 0
    pb_violations = 0
    pb_bad_healing = 0
    
    violation_count = 0
    visible_audit_count = 0
    rejected_count = 0
    top_suggestions = []
    
    swallowed = 0
    original_returned = 0
    progressive = 0
    overlay = 0
    max_visible_per_req = 0
    
    with open(log_file, 'r') as f:
        for line in f:
            if '[PromptBuilderMode]' in line:
                if 'mode=afterSpace' in line: pb_afterSpace += 1
                elif 'mode=midWord' in line: pb_midWord += 1
                
                if 'violation=trailingSpaceTrimmed' in line: pb_violations += 1
                if 'activeLineEndsWithWhitespace=true' in line and 'requiresHealing=true' in line:
                    pb_bad_healing += 1
                    
            elif '[PromptIsolation]' in line:
                if 'violation=' in line: violation_count += 1
                
            elif '[VisibleSuggestionAudit]' in line:
                if 'decision=visibleApplied' in line:
                    visible_audit_count += 1
                    sug_match = re.search(r"finalSuggestion='([^']*)'", line)
                    active_match = re.search(r"activeLine='([^']*)'", line)
                    mode_match = re.search(r"mode=([\w]+)", line)
                    partial_match = re.search(r"partialWord='([^']*)'", line)
                    raw_match = re.search(r"rawOutput='([^']*)'", line)
                    
                    if sug_match and active_match and mode_match and partial_match and raw_match:
                        top_suggestions.append({
                            'activeLine': active_match.group(1),
                            'mode': mode_match.group(1),
                            'partialWord': partial_match.group(1),
                            'rawOutput': raw_match.group(1),
                            'finalSuggestion': sug_match.group(1)
                        })
                        
                    count_match = re.search(r'visibleApplyCountForRequest=(\d+)', line)
                    if count_match:
                        count = int(count_match.group(1))
                        if count > max_visible_per_req:
                            max_visible_per_req = count
                            
                elif 'decision=rejectedBeforeVisible' in line:
                    rejected_count += 1
                    
            elif 'swallowed=true' in line: swallowed += 1
            elif 'originalReturned=false' in line: original_returned += 1
            elif 'progressiveRenderViolation' in line: progressive += 1
            elif 'layerCountAfter' in line:
                match = re.search(r'layerCountAfter=(\d+)', line)
                if match and int(match.group(1)) > 1:
                    overlay += 1

    print(f"PromptBuilderMode afterSpace: {pb_afterSpace}")
    print(f"PromptBuilderMode midWord: {pb_midWord}")
    print(f"PromptBuilderMode trailingSpaceTrimmed violations: {pb_violations}")
    print(f"PromptBuilderMode requiresHealing while activeLineEndsWithWhitespace: {pb_bad_healing}")
    
    print(f"\nprompt isolation violations: {violation_count}")
    print(f"VisibleSuggestionAudit visibleApplied count: {visible_audit_count}")
    print(f"rejectedBeforeVisible count: {rejected_count}")
    
    print("\nTop 20 visible suggestions:")
    for s in top_suggestions[:20]:
        print(f"  mode={s['mode']} partial='{s['partialWord']}' raw='{s['rawOutput']}' sug='{s['finalSuggestion']}' active='{s['activeLine']}'")
        
    print(f"\nvisible applies per request max: {max_visible_per_req}")
    print(f"progressiveRenderViolation count: {progressive}")
    print(f"swallowed=true count: {swallowed}")
    print(f"originalReturned=false count: {original_returned}")
    print(f"overlay layerCountAfter > 1 count: {overlay}")

    bad_words = ["good by good", "but there"]
    bad_gener = False
    visible_bad = []
    for s in top_suggestions:
        if s['finalSuggestion'].strip().lower() in bad_words:
            visible_bad.append(s['finalSuggestion'])
        if s['partialWord'] == 'gener' and s['finalSuggestion'] == 'at':
            bad_gener = True
            
    print(f"\nDo bad accepted suggestions still appear? {list(set(visible_bad))}, gener->at: {bad_gener}")

parse_logs('typeflow_live.log')
