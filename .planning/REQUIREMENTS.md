# Requirements

## v1 Requirements

### Core Injection (CORE)
- [ ] **CORE-01**: System-wide text field monitoring via Accessibility API
- [ ] **CORE-02**: Floating transparent overlay window anchored to caret coordinates
- [ ] **CORE-03**: Inject ghost-text inline
- [ ] **CORE-04**: Accept next word with Tab
- [ ] **CORE-05**: Accept full line with configurable hotkey
- [ ] **CORE-06**: Sub-150ms total completion cycle time

### AI & Inference (AI)
- [ ] **AI-01**: Local LLM inference via Apple MLX
- [ ] **AI-02**: Fast model vs Quality model auto-switching based on context length
- [ ] **AI-03**: Zero network calls for inference

### Context Pipeline (CTX)
- [ ] **CTX-01**: Active text context via Accessibility API
- [ ] **CTX-02**: Surrounding screen text via Vision framework OCR
- [ ] **CTX-03**: Clipboard contents context
- [ ] **CTX-04**: Date/time awareness injection

### Menu & Settings (UI)
- [ ] **UI-01**: Launch at login
- [ ] **UI-02**: Menu bar icon with quick actions (disable, words saved, settings)
- [ ] **UI-03**: Multi-pane SwiftUI Settings window (Setup, General, Context, etc.)
- [ ] **UI-04**: Suggestion delay and opacity sliders

### Personalization (PERS)
- [ ] **PERS-01**: Custom AI instructions textarea with per-app overrides
- [ ] **PERS-02**: Tone detection and profile management
- [ ] **PERS-03**: Snippet auto-detection and manual shortcodes
- [ ] **PERS-04**: Custom hotkeys for alternative actions (rewrite, cycle tone)

### App Control (APP)
- [ ] **APP-01**: Per-app disable/enable toggles
- [ ] **APP-02**: Per-app and per-domain (browser) overrides (model, tone, length)

## v2 Requirements
- Syncing custom instructions via iCloud (if privacy allows)

## Out of Scope
- Cloud-based LLM APIs (violates privacy and latency)
- Non-Apple Silicon Macs (requires MLX)

## Traceability
*(To be filled by roadmap)*
