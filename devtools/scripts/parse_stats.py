import re
import statistics
import sys

def parse_logs(log_file):
    clipboard_count = 0
    ocr_count = 0
    universal_count = 0
    violation_count = 0
    prompt_lens = []
    
    visible_applies = 0
    visible_audit_count = 0
    source_breakdown = {}
    top_suggestions = []
    
    spellcheck_suppressed = 0
    spellcheck_applied = 0
    
    with open(log_file, 'r') as f:
        for line in f:
            if '[PromptIsolation]' in line:
                if 'clipboardIncluded=true' in line: clipboard_count += 1
                elif 'ocrIncluded=true' in line: ocr_count += 1
                elif 'universalContextIncluded=true' in line: universal_count += 1
                elif 'violation=' in line: violation_count += 1
                
                match = re.search(r'fullPromptLen=(\d+)', line)
                if match: prompt_lens.append(int(match.group(1)))
                
            elif '[VisibleSuggestionAudit]' in line:
                if 'decision=visibleApplied' in line:
                    visible_audit_count += 1
                    # Extract source
                    src_match = re.search(r'source=([\w-]+)', line)
                    if src_match:
                        src = src_match.group(1)
                        source_breakdown[src] = source_breakdown.get(src, 0) + 1
                        
                    # Extract suggestion
                    sug_match = re.search(r"finalSuggestion='([^']+)'", line)
                    if sug_match:
                        top_suggestions.append(sug_match.group(1))
                        
            elif '[SpellcheckGhost]' in line:
                if 'suppressed' in line: spellcheck_suppressed += 1
                elif 'visibleApplied' in line: spellcheck_applied += 1
                
            elif 'updateAutocompleteText' in line and 'isSpellCorrection=false' in line:
                # Approximate overlay applies count if needed
                visible_applies += 1
                
    if prompt_lens:
        avg_len = sum(prompt_lens) / len(prompt_lens)
        prompt_lens.sort()
        p50 = statistics.median(prompt_lens)
        idx90 = int(len(prompt_lens) * 0.9)
        p90 = prompt_lens[idx90] if idx90 < len(prompt_lens) else prompt_lens[-1]
    else:
        avg_len = p50 = p90 = 0
        
    print(f"clipboardIncluded count: {clipboard_count}")
    print(f"ocrIncluded count: {ocr_count}")
    print(f"universalContextIncluded count: {universal_count}")
    print(f"prompt isolation violation count: {violation_count}")
    print(f"fullPromptLen: avg={avg_len:.1f}, p50={p50}, p90={p90}")
    
    print(f"visible overlay applies count (approx): {visible_applies}")
    print(f"VisibleSuggestionAudit visibleApplied count: {visible_audit_count}")
    print(f"source breakdown: {source_breakdown}")
    print(f"top visible suggestions: {top_suggestions[:20]}")
    
    print(f"SpellcheckGhost suppressed count: {spellcheck_suppressed}")
    print(f"SpellcheckGhost visibleApplied count: {spellcheck_applied}")

parse_logs('typeflow_live.log')
