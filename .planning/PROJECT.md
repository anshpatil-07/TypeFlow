# TypeFlow

## What This Is

TypeFlow is a system-wide AI autocomplete macOS menu bar app that works in every Mac application. It monitors the active text field using Accessibility APIs and injects ghost-text completions inline, powered by a local LLM running entirely on-device via Apple's MLX framework. It provides contextual completions by combining active text, surrounding screen text via Vision OCR, and clipboard contents.

## Core Value

Provide instantaneous (under 150ms), entirely on-device system-wide text completions that are context-aware and respect user privacy.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

(None yet — ship to validate)

### Active

<!-- Current scope. Building toward these. -->

- [ ] System-wide Accessibility API integration for text field monitoring and inline injection
- [ ] On-device local LLM inference via Apple MLX (Gemma 4 E2B or Qwen 2.5 1.5B) using Neural Engine
- [ ] Performance target: < 150ms from keystroke to completion injection
- [ ] Multi-source context pipeline (Accessibility text, periodic Vision OCR screenshots, clipboard)
- [ ] Settings screens: Setup, General, Context, Personalization, Tone profiles, Snippets, Shortcuts, App settings, Labs, Statistics
- [ ] Menu bar dropdown with quick actions (disable toggle, words saved, settings access)
- [ ] On-device only, zero network calls for inference or context processing
- [ ] Tone detection and profile management (built-in and custom)
- [ ] Snippet detection and management
- [ ] Custom shortcuts for different completion types (word, line, paragraph, alternatives)
- [ ] App-specific overrides (on/off, tone, model, completion length)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Cloud-based LLM APIs — Must be entirely on-device to ensure privacy and meet 150ms latency target
- Non-Apple Silicon Macs — Requires MLX and Neural Engine for on-device performance (macOS 14+ Apple Silicon only)

## Context

- Target OS: macOS 14+ Apple Silicon only
- Core Technologies: Swift, SwiftUI, Accessibility API, Apple Vision framework, MLX Swift
- Local LLM Models: Gemma 4 E2B or Qwen 2.5 1.5B as starting points
- Privacy is paramount: all processing, history tracking, and snippet generation happens on-device with encrypted local storage (Keychain).

## Constraints

- **Performance**: Under 150ms total completion cycle time — Crucial for natural typing experience; slower suggestions will be disruptive and rejected by users.
- **Privacy**: No network calls for inference — User context (screen, clipboard, typing) must never leave the device.
- **Platform**: Apple Silicon macOS 14+ only — Required for MLX and Vision APIs performance.
- **Tech Stack**: Swift and SwiftUI — Native performance and deep macOS integration.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Local LLM via MLX | Privacy and latency requirements dictate on-device inference using Neural Engine | — Pending |
| Vision OCR for context | Need surrounding context that Accessibility API might miss without complex integrations | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-22 after initialization*
