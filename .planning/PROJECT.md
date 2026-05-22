# TypeFlow

## What This Is

TypeFlow is a system-wide AI autocomplete macOS menu bar app that works in every Mac application. It monitors the active text field using Accessibility APIs and injects ghost-text completions inline, powered by a local LLM running entirely on-device via Apple's MLX framework. It provides contextual completions by combining active text, surrounding screen text via Vision OCR, and clipboard contents.

## Core Value

Provide instantaneous (under 150ms), entirely on-device system-wide text completions that are context-aware and respect user privacy.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ System-wide Accessibility API integration for text field monitoring and inline injection — v1.0
- ✓ On-device local LLM inference via Apple MLX using Neural Engine — v1.0
- ✓ Performance target: < 150ms from keystroke to completion injection — v1.0
- ✓ Multi-source context pipeline (Accessibility text, periodic Vision OCR screenshots, clipboard) — v1.0
- ✓ Settings screens: General, Persona, Snippets, Apps — v1.0
- ✓ Menu bar dropdown with quick actions (settings access) — v1.0
- ✓ On-device only, zero network calls for inference or context processing — v1.0
- ✓ Tone detection and profile management (built-in and custom) — v1.0
- ✓ Snippet detection and management — v1.0
- ✓ Custom shortcuts for full line completion — v1.0
- ✓ App-specific overrides (on/off, tone, model, completion length) — v1.0

### Active

<!-- Current scope. Building toward these. -->

- [ ] Syncing custom instructions via iCloud (if privacy allows)
- [ ] Model downloads UI and auto-updates
- [ ] Usage statistics and analytics dashboard
- [ ] Paragraph completion and alternatives cycler

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Cloud-based LLM APIs — Must be entirely on-device to ensure privacy and meet 150ms latency target
- Non-Apple Silicon Macs — Requires MLX and Neural Engine for on-device performance (macOS 14+ Apple Silicon only)

## Context

- Target OS: macOS 14+ Apple Silicon only
- Core Technologies: Swift, SwiftUI, Accessibility API, Apple Vision framework, MLX Swift
- Shipped v1.0 milestone with 761 lines of Swift code.
- Fully supports background operation as a menu bar extra (LSUIElement).
- Privacy is paramount: all processing, history tracking, and snippet generation happens on-device with encrypted local storage (Keychain).

## Constraints

- **Performance**: Under 150ms total completion cycle time — Crucial for natural typing experience; slower suggestions will be disruptive and rejected by users.
- **Privacy**: No network calls for inference — User context (screen, clipboard, typing) must never leave the device.
- **Platform**: Apple Silicon macOS 14+ only — Required for MLX and Vision APIs performance.
- **Tech Stack**: Swift and SwiftUI — Native performance and deep macOS integration.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Local LLM via MLX | Privacy and latency requirements dictate on-device inference using Neural Engine | ✓ Good |
| Vision OCR for context | Need surrounding context that Accessibility API might miss without complex integrations | ✓ Good |
| App as LSUIElement | A system-wide background utility shouldn't clog the dock. Requires manual NSWindow management for Settings | ✓ Good |

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
