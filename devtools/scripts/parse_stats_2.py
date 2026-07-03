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
    
    rejected_count = 0
    rejection_reasons = {}
    top_rejected = []
    
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
                    src_match = re.search(r'source=([\w-]+)', line)
                    if src_match:
                        src = src_match.group(1)
                        source_breakdown[src] = source_breakdown.get(src, 0) + 1
                    sug_match = re.search(r"finalSuggestion='([^']+)'", line)
                    active_match = re.search(r"activeLine='([^']+)'", line)
                    mode_match = re.search(r"mode=([\w]+)", line)
                    partial_match = re.search(r"partialWord='([^']*)'", line)
                    if sug_match and active_match and mode_match and partial_match:
                        top_suggestions.append({
                            'activeLine': active_match.group(1),
                            'mode': mode_match.group(1),
                            'partialWord': partial_match.group(1),
                            'finalSuggestion': sug_match.group(1)
                        })
                elif 'decision=rejectedBeforeVisible' in line:
                    rejected_count += 1
                    reason_match = re.search(r'reason=([\w]+)', line)
                    if reason_match:
                        reason = reason_match.group(1)
                        rejection_reasons[reason] = rejection_reasons.get(reason, 0) + 1
                    
                    sug_match = re.search(r"finalSuggestion='([^']*)'", line)
                    active_match = re.search(r"activeLine='([^']*)'", line)
                    if sug_match and reason_match:
                        top_rejected.append({
                            'activeLine': active_match.group(1) if active_match else '',
                            'suggestion': sug_match.group(1),
                            'reason': reason_match.group(1)
                        })
                        
            elif '[SpellcheckGhost]' in line:
                if 'suppressed' in line: spellcheck_suppressed += 1
                elif 'visibleApplied' in line: spellcheck_applied += 1
                
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
    
    print(f"VisibleSuggestionAudit visibleApplied count: {visible_audit_count}")
    print(f"source breakdown: {source_breakdown}")
    
    print("\nTop 20 visible suggestions:")
    for s in top_suggestions[:20]:
        print(f"  mode={s['mode']} partial='{s['partialWord']}' sug='{s['finalSuggestion']}' active='{s['activeLine'][-40:]}'")
        
    print(f"\nrejectedBeforeVisible count: {rejected_count}")
    print(f"rejection reasons: {rejection_reasons}")
    
    print("\nTop 20 rejected suggestions:")
    for s in top_rejected[:20]:
        print(f"  reason={s['reason']} sug='{s['suggestion']}' active='{s['activeLine'][-40:]}'")
        
    print(f"\nSpellcheckGhost suppressed count: {spellcheck_suppressed}")
    print(f"SpellcheckGhost visibleApplied count: {spellcheck_applied}")
    
    # Check if bad words still appeared visibly
    bad_words = ["andy", "bo", "ata", "anta", "yson", "ord", "1 had", "pped"]
    visible_bad = []
    for s in top_suggestions:
        if s['finalSuggestion'].strip().lower() in bad_words:
            visible_bad.append(s['finalSuggestion'])
    print(f"\nDo bad words still appear visibly? {list(set(visible_bad))}")

parse_logs('typeflow_live.log')
