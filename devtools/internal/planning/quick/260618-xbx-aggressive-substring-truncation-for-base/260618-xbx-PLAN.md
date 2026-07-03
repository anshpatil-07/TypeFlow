---
plan: 260618-xbx
phase: quick
status: pending
dependencies: []
---

# Plan: Aggressive Substring Truncation for Base Model Leakage

This plan implements aggressive substring truncation in the generation pipeline of `LLMEngine` to strip hallucinated control tags like `<|im_start|>` that are leaked by the base model.

## Proposed Changes

### 1. Update Truncation logic in `LLMEngine.swift`
- **File:** [LLMEngine.swift](file:///Users/anshalankarpatil/Documents/cotyper/TypeFlow/Services/LLMEngine.swift)
- **Action:** [MODIFY]
- **Details:** Truncate output at either a newline or the opening bracket of a control tag (`<`), clean the substring by trimming trailing whitespace, and discard the `<` and everything after it.

## Verification Plan
- Build the project using `xcodebuild` to ensure the compilation succeeds.
