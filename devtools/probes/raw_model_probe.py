import sys
import json
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
    "we need the suggestion to "
]

def run_sweep(name, **kwargs):
    print(f"\n=== Sweep: {name} ===")
    print(f"Settings: {kwargs}")
    for prompt in prompts:
        # Generate raw
        output = llm.create_completion(
            prompt,
            max_tokens=20,
            echo=False,
            **kwargs
        )
        tokens = llm.tokenize(prompt.encode('utf-8'))
        gen_text = output['choices'][0]['text']
        gen_tokens = llm.tokenize(gen_text.encode('utf-8'))
        
        # Sanitize text for console printing
        safe_prompt = prompt.replace("\n", "\\n")
        safe_gen = gen_text.replace("\n", "\\n")
        
        print(f"Prompt: '{safe_prompt}'")
        print(f"Prompt IDs: {tokens}")
        print(f"Gen Text: '{safe_gen}'")
        print(f"Gen IDs: {gen_tokens[:10]}")
        print("---")

run_sweep("Greedy", temperature=0.0)
run_sweep("Low Temp", temperature=0.2, top_p=0.9, top_k=20)
run_sweep("TypeFlow Default", temperature=0.2) # TypeFlow uses 0.2 if no config
