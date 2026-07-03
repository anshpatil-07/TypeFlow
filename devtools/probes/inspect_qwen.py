import sys
from llama_cpp import Llama

model_path = "/Users/anshalankarpatil/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf"

print(f"Loading metadata for {model_path}...")
try:
    llm = Llama(model_path=model_path, verbose=False)
except Exception as e:
    print(f"Failed to load: {e}")
    sys.exit(1)

meta = llm.metadata
keys_to_print = [
    "general.name",
    "general.architecture",
    "general.quantization_version",
    "tokenizer.ggml.model",
    "qwen2.context_length",
    "tokenizer.ggml.bos_token_id",
    "tokenizer.ggml.eos_token_id",
    "tokenizer.chat_template"
]

print("=== Metadata ===")
for k, v in meta.items():
    if "fim" in k.lower() or "middle" in k.lower() or "suffix" in k.lower() or "prefix" in k.lower():
        print(f"{k}: {v}")
    elif k in keys_to_print:
        print(f"{k}: {v}")

print("=== Vocab Search ===")
tokens_to_search = ["<|fim_prefix|>", "<|fim_suffix|>", "<|fim_middle|>", "<fim_prefix>", "<fim_suffix>", "<fim_middle>"]
for t in tokens_to_search:
    try:
        # Some tokenizers handle special tokens, let's just search the vocab if possible
        b = t.encode('utf-8')
        tid = llm.tokenize(b, special=True)
        if len(tid) == 1:
            # Maybe it's a special token? But llama_cpp adds BOS sometimes. Let's see.
            # Qwen uses <|fim_prefix|> etc.
            pass
        print(f"Token '{t}' -> IDs: {tid}")
    except Exception as e:
        print(f"Token '{t}' error: {e}")

# We can also iterate vocab explicitly using llama_cpp
try:
    for i in range(llm.n_vocab()):
        token_str = llm.detokenize([i]).decode('utf-8', errors='ignore')
        if "fim" in token_str.lower():
            print(f"Vocab ID {i}: {token_str}")
except Exception as e:
    pass
