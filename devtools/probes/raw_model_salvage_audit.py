import sys
import re

try:
    from llama_cpp import Llama
except ImportError:
    print("llama-cpp-python not installed")
    sys.exit(1)

model_path = "/Users/anshalankarpatil/Documents/gemma-4-E2B-i1-Q4_K_M.gguf"
llm = Llama(model_path=model_path, verbose=False)

prompts = [
    "The quick brown ",
    "Once upon a time ",
    "I want the ghost text to feel natural ",
    "there is a more pressing matter at hand ",
    "the quality of generation is still not good ",
    "this completion should be useful because ",
    "we need the suggestion to ",
    "public ResponseEntity<User> getUserById(",
    "SELECT * FROM users WHERE "
]

def salvage(raw_text, active_line, mode):
    # Mode 1: strict baseline
    if mode == 1:
        return raw_text

    text = raw_text
    
    # Mode 2, 3, 4:
    # 4. Explanation truncation
    truncation_markers = ["Explanation:", "Note:", "Output:", "\n\n"]
    for marker in truncation_markers:
        if marker in text:
            text = text.split(marker)[0]

    # 1. HTML/XML tag stripping
    text = re.sub(r'<[^>]+>', '', text)
    
    # 2. Markdown stripping
    text = re.sub(r'\*{1,3}([^\*]+)\*{1,3}', r'\1', text)
    text = re.sub(r'_{1,3}([^_]+)_{1,3}', r'\1', text)
    text = re.sub(r'`([^`]+)`', r'\1', text)
    
    if mode == 3:
        # Mode 3: Plus List Prefix
        text = re.sub(r'^[\s]*[\d]+[\)\.]\s+', '', text)
        text = re.sub(r'^[\s]*[\-\*]\s+', '', text)
        
    if mode == 4:
        # Mode 4: firstPhraseExtractor (same stripping as Mode 2)
        pass # Truncation logic applied later

    # Normalize whitespace/punctuation
    text = text.lstrip(" \t\n\r,-:;")
    
    # Stop at newline
    text = text.split('\n')[0]
    
    # Active line prefix stripping
    lower_s = text.lower().strip()
    lower_active = active_line.lower().strip()
    if lower_active and lower_s.startswith(lower_active) and len(lower_s) > len(lower_active):
        text = text[text.lower().find(lower_active) + len(lower_active):].lstrip(" \t,-:;")
        
    if mode == 4:
        # keep 1-5 words, stop at sentence boundary
        text = re.split(r'[\.\!\?]', text)[0]
        words = text.split()
        if len(words) > 5:
            text = " ".join(words[:5])

    return text.strip()

def check_malformed_quote(text):
    if not text: return False
    # valid: I'm, don't, it's, we're, user's
    if text.startswith("I\"") or text == "I'": return True
    if text.startswith("'") or text.endswith("'"): return True
    if text.startswith("\"") or text.endswith("\""): return True
    # Quote-only or punctuation only
    if not any(c.isalnum() for c in text): return True
    return False

def check_active_line_restart(cleaned, active):
    cleaned_norm = " ".join(re.sub(r'[^\w\s]', '', cleaned).lower().split())
    active_norm = " ".join(re.sub(r'[^\w\s]', '', active).lower().split())
    if not cleaned_norm or not active_norm:
        return False
    # Exact full copy then divergence is handled by overlap stripping. 
    # If cleaned starts with substantial prefix of active line (e.g. first 3 words), it's a restart.
    active_words = active_norm.split()
    cleaned_words = cleaned_norm.split()
    
    # Check if cleaned rewrites active line
    if len(active_words) >= 3 and len(cleaned_words) >= 3:
        if cleaned_words[:3] == active_words[:3]:
            return True
        # Check partial rewrite like "the quality generation" for "the quality of generation"
        if cleaned_words[0] == active_words[0] and cleaned_words[1] == active_words[1]:
            return True
    return False

def check_generic_fragment(text):
    generics = ["it is a good", "this is a", "there are", "the more", "states that"]
    text_lower = text.lower()
    return any(text_lower == g or text_lower.startswith(g + " ") for g in generics)

def salvage_decision(salvaged_text, active_line, raw):
    if not salvaged_text:
        return False, "empty"
    
    if check_malformed_quote(salvaged_text):
        return False, "malformedQuote"
        
    if check_active_line_restart(salvaged_text, active_line):
        return False, "activeLineRestart"
        
    if check_generic_fragment(salvaged_text):
        return False, "genericFragment"
        
    if "<" in salvaged_text and ">" in salvaged_text:
        return False, "markupResidue"
        
    return True, "pass"

print("Offline Salvage Audit starting...")

for mode in [1, 2, 3, 4]:
    print(f"\n=========================================")
    print(f"MODE {mode}")
    print(f"=========================================")
    
    total = 0
    strict_acc = 0
    salv_acc = 0
    rej_active = 0
    rej_quote = 0
    rej_markup = 0
    rej_generic = 0
    
    for prompt in prompts:
        for i in range(3):
            # Deterministic for offline audit
            output = llm.create_completion(prompt, max_tokens=20, echo=False, temperature=0.0)
            raw = output['choices'][0]['text']
            
            # Strict mode 1 logic (baseline)
            strict_dec = False if ("<" in raw or "\n" in raw or "1)" in raw) else True
            if strict_dec: strict_acc += 1
            
            salv = salvage(raw, prompt, mode)
            salv_dec, salv_reason = salvage_decision(salv, prompt, raw)
            
            total += 1
            if salv_dec: 
                salv_acc += 1
            else:
                if salv_reason == "activeLineRestart": rej_active += 1
                if salv_reason == "malformedQuote": rej_quote += 1
                if salv_reason == "markupResidue": rej_markup += 1
                if salv_reason == "genericFragment": rej_generic += 1
            
            if mode == 4:
                safe_raw = raw.replace("\n", "\\n")
                print(f"[{i}] Prompt: '{prompt}'")
                print(f"    Raw: '{safe_raw}'")
                print(f"    Sal: '{salv}' -> {salv_dec} ({salv_reason})")
                
    print(f"Totals Mode {mode}: Raw: {total}, Strict Acc: {strict_acc}, Salvage Acc: {salv_acc}")
    print(f"Rejections Mode {mode}: ActiveRestart: {rej_active}, MalformedQuote: {rej_quote}, MarkupResidue: {rej_markup}, Generic: {rej_generic}")
