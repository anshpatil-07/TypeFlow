---
plan: 260612-kmg
phase: quick
status: pending
dependencies: []
---

# Plan: Fix KV Cache Contamination and Prewarm Cache Format Mismatch

This plan resolves the Gemma 4 autocomplete issue where the model hallucinations/instructions leak into the autocomplete overlay. It targets two root causes:
1. **Pre-warm format mismatch**: `prewarmCache` uses a legacy prompt format `buildStaticPrefix`, while `generateCompletion` uses the new `<start_of_turn>` instruct template format, leading to an immediate cache miss and incorrect evaluations.
2. **KV cache contamination**: The generator appends generated tokens directly to the cache, corrupting the context for future keystrokes since the circular `RotatingKVCache` in Gemma 4's sliding window layers cannot be trimmed back.

## Proposed Changes

### 1. Align Pre-warm Prompt Format
- **File:** [PromptBuilder.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/PromptBuilder.swift)
- **Action:** [MODIFY]
- **Details:** Update `buildStaticPrefix` to return `buildPromptPrefix(systemInstructions: systemInstructions)`. This ensures the pre-warmed prefix matches the actual generation prefix exactly.

### 2. Copy and Reset KV Cache
- **File:** [LLMEngine.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/LLMEngine.swift)
- **Action:** [MODIFY]
- **Details:**
  - If `tokensToTrim > 0`, check if the cache is trimmable using `canTrimPromptCache(cache)`. If not, reset `self.kvCache = nil; self.cachedTokens = []`, create a new cache, update `cache`, and set `lcpIndex = 0`.
  - Copy the cache `let generatorCache = cache.map { $0.copy() }` and pass `generatorCache` to `generate`.
  - Evaluate `suffixTokens` synchronously on the original `cache` if `!suffixTokens.isEmpty` using `modelContext.model(suffixMLXTokens[.newAxis], cache: cache)` and `eval(cache)`, and update `self.cachedTokens = fullTokens`.

## Verification Plan
- Verify that typing in any app tap-injects completions cleanly without echoing system prompt/formatting instructions.
- Check console logs to ensure `Pre-warm cache hit — reusing KV prefix` is logged and `tokensToTrim` is 0 during sequential typing.
