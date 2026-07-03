import sys
import re
from collections import Counter

def is_punctuation_only(text):
    if not text: return False
    return all(not c.isalnum() and not c.isspace() for c in text.strip())

def is_whitespace_only(text):
    if not text: return False
    return all(c.isspace() for c in text)

def analyze_log(path):
    print(f"Analyzing {path}...")
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"File {path} not found.")
        return

    counts = Counter()
    sources = Counter()
    accepted_examples = []
    rejected_examples = []

    # Map requestID to detailed info
    requests = {}

    for line in lines:
        if "[QualityAudit] requestID=" in line and "phase=" in line:
            # e.g. [QualityAudit] requestID=4 phase=stream textBeforeCaret='...' rawOutput='nt' processedOutput='nt' accepted=true rejectionReason=none
            req_id_match = re.search(r"requestID=(\d+)", line)
            if req_id_match:
                req_id = req_id_match.group(1)
                
                raw_out_match = re.search(r"rawOutput='((?:\\'|[^'])*)'", line)
                proc_out_match = re.search(r"processedOutput='((?:\\'|[^'])*)'", line)
                rej_reason_match = re.search(r"rejectionReason=([\w-]+)", line)
                accepted_match = re.search(r"accepted=(true|false)", line)
                
                if req_id not in requests:
                    requests[req_id] = {}
                if raw_out_match: requests[req_id]['raw'] = raw_out_match.group(1).replace("\\'", "'")
                if proc_out_match: requests[req_id]['proc'] = proc_out_match.group(1).replace("\\'", "'")
                if rej_reason_match: requests[req_id]['reason'] = rej_reason_match.group(1)
                if accepted_match: requests[req_id]['accepted'] = accepted_match.group(1) == 'true'

        elif "[QualityAudit] reason=" in line:
            # e.g. [QualityAudit] reason=validContinuation source=AXValue activeLine='...' finalSuggestion='nt'
            req_id = None
            # Need to match this to a requestID. Unfortunately, this line doesn't log requestID!
            # Wait, the previous log output showed requestID was extracted from the other line.
            pass

    # Let's do a multi-pass or stateful pass.
    # Group by consecutive QualityAudit lines or just use the phase=stream line since it contains rawOutput, processedOutput, rejectionReason
    for req_id, data in requests.items():
        raw = data.get('raw', '')
        proc = data.get('proc', '')
        reason = data.get('reason', 'none')
        accepted = data.get('accepted', False)

        # Re-derive source and activeLine by scanning again?
        # Actually, let's just do a simple state machine per line.
        pass

    # New state machine approach
    current_req = {}
    
    for line in lines:
        if "[QualityAudit] requestID=" in line and "phase=" in line:
            req_id_match = re.search(r"requestID=(\d+)", line)
            raw_out_match = re.search(r"rawOutput='((?:\\'|[^'])*)'", line)
            proc_out_match = re.search(r"processedOutput='((?:\\'|[^'])*)'", line)
            rej_reason_match = re.search(r"rejectionReason=([\w-]+)", line)
            accepted_match = re.search(r"accepted=(true|false)", line)
            text_before_match = re.search(r"textBeforeCaret='((?:\\'|[^'])*)'", line)

            if req_id_match:
                current_req['id'] = req_id_match.group(1)
                if raw_out_match: current_req['raw'] = raw_out_match.group(1).replace("\\'", "'")
                if proc_out_match: current_req['proc'] = proc_out_match.group(1).replace("\\'", "'")
                if rej_reason_match: current_req['reason'] = rej_reason_match.group(1)
                if accepted_match: current_req['accepted'] = accepted_match.group(1) == 'true'
                if text_before_match: current_req['textBeforeCaret'] = text_before_match.group(1).replace("\\'", "'")
                
        elif "[QualityAudit] reason=" in line and "source=" in line:
            if not current_req: continue
            
            source_match = re.search(r"source=([\w-]+)", line)
            active_line_match = re.search(r"activeLine='((?:\\'|[^'])*)'", line)
            reason_match = re.search(r"reason=([\w-]+)", line)
            final_match = re.search(r"finalSuggestion='((?:\\'|[^'])*)'", line)
            
            if source_match:
                sources[source_match.group(1)] += 1
                current_req['source'] = source_match.group(1)
            
            active_line = active_line_match.group(1).replace("\\'", "'") if active_line_match else ""
            current_req['activeLine'] = active_line
            final_sug = final_match.group(1).replace("\\'", "'") if final_match else ""
            
            raw = current_req.get('raw', '')
            reason = reason_match.group(1) if reason_match else current_req.get('reason', '')
            accepted = current_req.get('accepted', reason == 'validContinuation')
            
            # Categorize
            is_punct_raw = is_punctuation_only(raw)
            is_space_raw = is_whitespace_only(raw)
            ends_with_space = active_line.endswith(" ") or active_line.endswith("\t")
            
            if accepted:
                if is_punct_raw:
                    counts['visiblePunctuationOnlyRendered'] += 1
                if ends_with_space:
                    counts['validAfterSpace'] += 1
                else:
                    counts['validMidWord'] += 1
                    
                if len(accepted_examples) < 5:
                    accepted_examples.append(f"activeLine: '{active_line}' -> raw: '{raw}' -> final: '{final_sug}'")
                    
            else:
                if is_punct_raw:
                    counts['rawPunctuationOnlyRejected'] += 1
                
                if reason == 'empty':
                    if is_punct_raw:
                        counts['emptyBecausePunctuationOnly'] += 1
                    elif is_space_raw:
                        counts['emptyBecauseWhitespaceOnly'] += 1
                    elif "overlap" in reason.lower() or "duplicate" in reason.lower() or final_sug == "":
                        # Heuristic for overlap if not punct/space but empty
                        counts['emptyBecausePureOverlap'] += 1
                    else:
                        counts['emptyBecauseOther'] += 1
                elif reason == 'repeatedTokenLoop':
                    counts['emptyBecauseRepeatedTokenLoop'] += 1
                
                if ends_with_space:
                    counts['rejectedAfterSpace'] += 1
                else:
                    counts['rejectedMidWord'] += 1
                    
                if len(rejected_examples) < 5:
                    rejected_examples.append(f"activeLine: '{active_line}' -> raw: '{raw}' -> reason: '{reason}'")

            current_req = {}

    print("=== METRICS ===")
    for k, v in counts.items():
        print(f"{k}: {v}")
    print("\n=== SOURCES ===")
    for k, v in sources.items():
        print(f"{k}: {v}")
    print("\n=== TOP ACCEPTED ===")
    for ex in accepted_examples:
        print(ex)
    print("\n=== TOP REJECTED ===")
    for ex in rejected_examples:
        print(ex)
    print("\n")

if __name__ == "__main__":
    analyze_log(sys.argv[1])
