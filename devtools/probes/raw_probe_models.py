import sys
import time

try:
    from llama_cpp import Llama
except ImportError:
    print("llama-cpp-python not installed")
    sys.exit(1)

model_paths = {
    "Baseline": "/Users/anshalankarpatil/Documents/gemma-4-E2B-i1-Q4_K_M.gguf",
    "Qwen-0.5B": "/Users/anshalankarpatil/Documents/Qwen2.5-0.5B-Coder-Q8_0.gguf",
    "Qwen-1.5B": "/Users/anshalankarpatil/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf"
}

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

print("Starting Direct Raw Probe...")

for name, path in model_paths.items():
    print(f"\n=========================================")
    print(f"MODEL: {name}")
    print(f"=========================================")
    try:
        llm = Llama(model_path=path, verbose=False)
    except Exception as e:
        print(f"Failed to load {name}: {e}")
        continue
        
    for prompt in prompts:
        t0 = time.time()
        # Stream to get first token latency
        generator = llm.create_completion(prompt, max_tokens=20, echo=False, temperature=0.0, stream=True)
        
        first_token = None
        t1 = None
        full_text = ""
        for chunk in generator:
            if t1 is None:
                t1 = time.time()
            text = chunk['choices'][0]['text']
            if first_token is None:
                first_token = text
            full_text += text
            
        t2 = time.time()
        
        first_ms = (t1 - t0) * 1000 if t1 else 0
        total_ms = (t2 - t0) * 1000
        tokens = len(llm.tokenize(full_text.encode('utf-8')))
        tps = tokens / (t2 - t1) if (t2 - t1) > 0 else 0
        
        safe_raw = full_text.replace('\n', '\\n')
        print(f"Prompt: '{prompt}'")
        print(f"  Raw: '{safe_raw}'")
        print(f"  First: {first_ms:.1f}ms | Total: {total_ms:.1f}ms | TPS: {tps:.1f}")
        
