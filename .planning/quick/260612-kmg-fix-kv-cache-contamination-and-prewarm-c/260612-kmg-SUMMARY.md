# Summary: Fix KV Cache Contamination and Prewarm Cache Format Mismatch

## Changes Implemented

### 1. Unified Pre-warm and Active Prompt Formats
- **File:** [PromptBuilder.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/PromptBuilder.swift)
- **Change:** Modified `buildStaticPrefix` to return `buildPromptPrefix(systemInstructions: systemInstructions)` directly.
- **Why:** The previous configuration pre-warmed a legacy prompt prefix structure, while active autocomplete calls constructed instruct prompts using `<start_of_turn>` templates. This resulted in an immediate divergence/cache miss on the first keystroke.

### 2. Copy-on-Generate & Non-trimmable Cache Reset Fallback
- **File:** [LLMEngine.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/LLMEngine.swift)
- **Change:**
  - Added a check in the cache trimming block. If `tokensToTrim > 0` but the cache is not trimmable (which is always true for Gemma 4 once it reaches sliding window rotation size), the engine discards `self.kvCache` and starts fresh with a newly allocated cache.
  - Copied the original cache before passing it to `generate` using `.map { $0.copy() }`. This allows the asynchronous generation process to populate the copy with generated tokens while the original cache remains clean of any hallucinated output.
  - Synchronously evaluated the prompt suffix tokens on the original cache right before beginning stream processing so that subsequent keystrokes only evaluate the single new character typed.

## Verification
- Project builds successfully: `** BUILD SUCCEEDED **`.
