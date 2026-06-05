---
phase: 17
plan: 01
subsystem: Core
tags: [Performance, Settings, Context, Prewarming]
requires: []
provides: [AppMonitor, Zero-Latency Prewarming]
affects: [SettingsManager, PromptBuilder, AccessibilityMonitor, LLMEngine]
tech-stack.added: [NSWorkspace.didActivateApplicationNotification]
tech-stack.patterns: [Event Observer, Caching, Token Prefilling]
key-files.modified: [TypeFlow/Services/SettingsManager.swift, TypeFlow/UI/SettingsView.swift, TypeFlow/Services/PromptBuilder.swift, TypeFlow/Services/LLMEngine.swift, TypeFlow/AppDelegate.swift, TypeFlow/Services/AccessibilityMonitor.swift]
key-files.created: [TypeFlow/Services/AppMonitor.swift]
key-decisions:
  - id: 17-01-D1
    description: "Skipped redundant appVoiceMap in favor of existing appConfigsData mapping for tone profiles."
  - id: 17-01-D2
    description: "Pre-warm cache triggers background pre-filling of static prefix tokens into MLX KV cache."
requirements-completed: []
duration: 5 min
completed: 2026-06-05T11:28:00Z
---

# Phase 17 Plan 01: Context & Zero-Latency Engine Summary

Context extraction expanded to 1000 characters, background KV cache prewarming implemented on app switch.

## Execution Details
- **Tasks Completed**: 4/4
- **Files Modified**: 6
- **Files Created**: 1
- **Start Time**: 2026-06-05T11:22:00Z
- **End Time**: 2026-06-05T11:28:00Z
- **Duration**: 5 min

## What Was Built
- Added `useBritishEnglish` toggle to `SettingsManager` and UI.
- Updated `PromptBuilder` to dynamically append regional spelling instructions to system prompts when enabled.
- Created `AppMonitor` to observe `NSWorkspace` for active application switches.
- Implemented `prewarmCache` in `LLMEngine` to asynchronously rebuild and cache the static prefix prompt tokens for the newly focused app's target tone profile.
- Increased `AccessibilityMonitor` extraction limit from 200 characters to 1,000 characters to provide deeper context to the LLM.

## Deviations from Plan
**[Rule 4 - Architectural] Use existing appConfigsData for tone mapping**
- Found during: Task 1
- Issue: Plan requested a new `appVoiceMap` dictionary in `SettingsManager`.
- Fix: The existing `appConfigsData` already maintains an `AppConfig` struct per bundle ID, which includes a `customTone` property. To prevent UI state desync and redundant data structures, `appVoiceMap` was skipped in favor of using the established `getEffectiveConfig` flow.
- Files modified: `SettingsManager.swift`
- Verification: Architectural decision presented and approved via user checkpoint.

## Issues Encountered
None.

## Next Phase Readiness
Phase complete, ready for next step.

## Self-Check: PASSED
