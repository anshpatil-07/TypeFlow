# TypeFlow State

## Current status
Completed:
- Stage 1A: latest-input-wins stale render guards
- Stage 1B: request-scoped llama.cpp cancellation
- Stage 2A: unified autocomplete debounce ownership
- Stage 2B: removed AX polling from stream/render hot paths
- Stage 3A: idempotent low-churn overlay rendering
- Stage 3B: browser/Codex editable AX element recovery for caret geometry
- Stage 3C: reduced first-visible render deferral and fixed render latency attribution
- Stage 4A: quality audit instrumentation
- Stage 4B: continuation post-processing contract
- Stage 4C-1: tightened inline continuation contract for invalid mid-word uppercase continuations and repeated-token loops
- Stage 5M-3: Production candidate validation and model metrics

### TypeFlow Production Status
Current Engine: Qwen2.5-Coder-1.5B (FIM)
Architecture: Apple MLX (mlx-swift)
Current Render Strategy: Atomic One-Visible-Apply
Input/Safety: AXUIElement + CGEvent (pass-through bounded)

### Stage 5M-3 Verdict: PRODUCTION_CANDIDATE_PASS

#### Quality & Prompt Mode
- **Mode:** Qwen FIM (`<|fim_prefix|>`, `<|fim_suffix|>`, `<|fim_middle|>`)
- **Prefix Bound:** Bounded to 512 chars (active typing context only).
- **Salvage Mode:** Disabled (Mode 0).
- **Observation:** Qwen FIM properly generates prose, code, and SQL completions. Stage 5M-1 bounds removed hallucinated markup and repeated context without requiring destructive salvage filters.

#### Latency Targets (Adaptive Debounce tuned to 25–75ms)
*Target: < 220–230ms p90*
- **Repeatability Test (3 runs):** 
  - p90 `totalPauseToVisibleMs`: **~165ms** (Range: 142ms - 170ms)
  - max `totalPauseToVisibleMs`: **~180ms** (Worst case: 198ms)
  - `firstUsableTokenMs` p90: **~89ms**
- **Stress Test (Burst/Backspacing):**
  - p90 `totalPauseToVisibleMs`: **129.8ms**
  - max `totalPauseToVisibleMs`: **179.2ms**

#### Stability & Input Safety
- **Visible Applies Max:** 1 (no flicker)
- **Progressive Render Violations:** 0
- **Swallowed Keys:** 0
- **Overlay Ghost Layers:** 0
- **Thrash/Stale Generations:** 0 (clean actor cancellation works under 220 WPM burst typing)
- **Browser Compatibility:** Passes scripted Safari textarea smoke tests (p90 183.6ms).

#### Configuration & Sandboxing
- Hardcoded absolute model paths removed from binary.
- Configured via `-modelPath` and `-modelProfileID`.
- FIM enablement strictly tied to the `modelProfileID` (fails closed if path is empty or token verification fails).

## Latest known good metrics
- Stage 3C renderMs around avg 8.2ms, p90 12.6ms
- Stage 4C-1 valid continuations: 112 (out of 120 completion records)
- Stage 4C-1 empty/rejected: 8
- Stage 4C-1 punctuation-only visible suggestions: 0
- Stage 4C-1 assistantLike: 0
- Stage 4C-1 OCR/context contamination: 0
- overlay layerCountAfter > 1: 0
- swallowed=true: 0
- originalReturned=false: 0
- Tests passed: `swift test_overlap.swift` (18/18 cases), `swift test_mem.swift`, `xcodebuild Debug build`

## Current next stage
Pause core pipeline changes. The responsiveness and quality stages are now in a good validated state. Next work should be release-candidate regression testing / product polish, not more prompt/model changes, unless a real quality issue appears.

## Guardrails
Do not modify unless explicitly asked:
- LLM/model
- sampler
- prompt construction
- OCR behavior
- debounce
- input handling
- overlay lifecycle/rendering
- Stage 1A/1B/2/3 behavior
- Stage 4B canonicalizer

## Testing commands
- swift test_overlap.swift
- swift test_mem.swift
- xcodebuild Debug build with full output redirected to a log file

## Log analysis workflow
Use .agents/skills/typeflow-log-auditor/.
Do not paste raw logs.
Run the auditor in full report mode and return the structured report.

## Tool split
- Antigravity: run tests, collect logs, use log auditor, produce structured reports, simple tooling/docs, bounded low-risk implementation
- ChatGPT: validate report/diagnosis and write exact implementation prompts
- Codex: high-risk implementation, architecture-sensitive fixes, final review
