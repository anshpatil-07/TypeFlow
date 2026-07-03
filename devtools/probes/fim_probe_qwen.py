import sys
import time

try:
    from llama_cpp import Llama
except ImportError:
    print("llama-cpp-python not installed")
    sys.exit(1)

model_path = sys.argv[1] if len(sys.argv) > 1 else "/Users/anshalankarpatil/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf"
print(f"Loading model {model_path} for FIM Probe...")
try:
    llm = Llama(model_path=model_path, verbose=False, n_ctx=2048)
except Exception as e:
    print(f"Failed to load: {e}")
    sys.exit(1)

# FIM format for Qwen2.5-Coder
# <|fim_prefix|> prefix <|fim_suffix|> suffix <|fim_middle|>
def build_fim_prompt(prefix, suffix):
    return f"<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>"

prefix_only = [
    "The quick brown ",
    "I want the ghost text to feel natural ",
    "there is a more pressing matter at hand ",
    "this completion should be useful because ",
    "we need the suggestion to ",
    "public ResponseEntity<User> getUserById(",
    "SELECT * FROM users WHERE "
]

true_infill = [
    ("The quick ", " jumped over the fence."),
    ("public ResponseEntity<User> ", " {"),
    ("SELECT * FROM ", " WHERE id = ?")
]

print("\n=== Prefix-Only / Empty Suffix FIM ===")
for p in prefix_only:
    prompt = build_fim_prompt(p, "")
    t0 = time.time()
    res = llm.create_completion(prompt, max_tokens=20, echo=False, temperature=0.1, top_p=0.9, top_k=50)
    t1 = time.time()
    
    text = res['choices'][0]['text'].replace('\n', '\\n')
    print(f"Prefix: '{p}'")
    print(f"  Raw output: '{text}'")
    print(f"  Latency: {(t1 - t0)*1000:.1f}ms")

print("\n=== True Infill FIM ===")
for p, s in true_infill:
    prompt = build_fim_prompt(p, s)
    t0 = time.time()
    res = llm.create_completion(prompt, max_tokens=20, echo=False, temperature=0.1, top_p=0.9, top_k=50)
    t1 = time.time()
    
    text = res['choices'][0]['text'].replace('\n', '\\n')
    print(f"Prefix: '{p}' | Suffix: '{s}'")
    print(f"  Raw output: '{text}'")
    print(f"  Latency: {(t1 - t0)*1000:.1f}ms")

