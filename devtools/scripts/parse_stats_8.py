import re
import sys
import statistics

def parse_logs(log_file):
    violation_count = 0
    visible_audit_count = 0
    rejected_count = 0
    top_suggestions = []
    
    swallowed = 0
    original_returned = 0
    progressive = 0
    overlay = 0
    max_visible_per_req = 0
    
    trailing_trim = 0
    requires_healing = 0
    
    promptSuffixLineCounts = []
    previousContextLens = []
    
    rejection_reasons = {}
    
    with open(log_file, 'r', errors='replace') as f:
        for line in f:
            if '[PromptContextWindow]' in line:
                if 'warning=tooManyLinesForInlineAutocomplete' not in line:
                    sc_match = re.search(r'promptSuffixLineCount=(\d+)', line)
                    pcl_match = re.search(r'previousContextLen=(\d+)', line)
                    if sc_match: promptSuffixLineCounts.append(int(sc_match.group(1)))
                    if pcl_match: previousContextLens.append(int(pcl_match.group(1)))
                        
            elif '[PromptBuilderMode]' in line:
                if 'violation=trailingSpaceTrimmed' in line: trailing_trim += 1
                if 'activeLineEndsWithWhitespace=true' in line and 'requiresHealing=true' in line:
                    requires_healing += 1
                    
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
                    reason_match = re.search(r'reason=([\w]+)', line)
                    if reason_match:
                        reason = reason_match.group(1)
                        rejection_reasons[reason] = rejection_reasons.get(reason, 0) + 1
                    
            elif 'swallowed=true' in line: swallowed += 1
            elif 'originalReturned=false' in line: original_returned += 1
            elif 'progressiveRenderViolation' in line: progressive += 1
            elif 'layerCountAfter' in line:
                match = re.search(r'layerCountAfter=(\d+)', line)
                if match and int(match.group(1)) > 1:
                    overlay += 1

    def stats(arr):
        if not arr: return "0/0/0"
        arr.sort()
        avg = sum(arr) / len(arr)
        p50 = statistics.median(arr)
        idx90 = int(len(arr) * 0.9)
        p90 = arr[idx90] if idx90 < len(arr) else arr[-1]
        return f"{avg:.1f}/{p50}/{p90}"

    print(f"promptSuffixLineCount avg/p50/p90: {stats(promptSuffixLineCounts)}")
    print(f"previousContextLen avg/p50/p90: {stats(previousContextLens)}")
    
    print(f"\ntrailingSpaceTrimmed violations: {trailing_trim}")
    print(f"requiresHealing while activeLineEndsWithWhitespace: {requires_healing}")
    print(f"prompt isolation violations: {violation_count}")
    
    print(f"\nafterSpaceVisibleApplied count: {len([s for s in top_suggestions if s['mode'] == 'afterSpace'])}")
    print(f"afterSpaceRejected count: {rejected_count}")
    
    print(f"Rejection counts by reason:")
    for k in sorted(rejection_reasons.keys()):
        print(f"  {k}: {rejection_reasons[k]}")
        
    print(f"\nvisible applies per request max: {max_visible_per_req}")
    print(f"progressiveRenderViolation: {progressive}")
    print(f"swallowed=true: {swallowed}")
    print(f"originalReturned=false: {original_returned}")
    print(f"overlay layerCountAfter > 1: {overlay}")
    
    print("\nTop 20 visible suggestions:")
    for s in top_suggestions[:20]:
        active_clean = s['activeLine'].replace('\n', '\\n')
        print(f"  mode={s['mode']} partial='{s['partialWord']}' raw='{s['rawOutput']}' sug='{s['finalSuggestion']}' active='{active_clean[-40:]}'")
        
parse_logs('typeflow_live.log')
