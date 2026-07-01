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

## Latest known good metrics
- Stage 3C totalPauseToVisibleMs around avg 114.6ms, p50 100.9ms, p90 171.6ms
- Stage 3C renderMs around avg 8.2ms, p90 12.6ms
- Stage 4B punctuation-only visible suggestions: 0
- Stage 4B repeated-token visible suggestions: 0
- Stage 4B overlay layerCountAfter > 1: 0
- swallowed=true: 0
- originalReturned=false: 0

## Current next stage
Stage 4C-0: prompt/model/OCR quality audit only.
Do not implement behavior changes until the audit report is reviewed.

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
