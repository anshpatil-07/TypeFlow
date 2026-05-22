# Requirements

## v1 Requirements

### Core Injection (CORE)
- [x] **CORE-01**: System-wide text field monitoring via Accessibility API
- [x] **CORE-02**: Floating transparent overlay window anchored to caret coordinates
- [x] **CORE-03**: Inject ghost-text inline
- [x] **CORE-04**: Accept next word with Tab
- [ ] **CORE-05**: Accept full line with configurable hotkey
- [x] **CORE-06**: Sub-150ms total completion cycle time

### AI & Inference (AI)
- [x] **AI-01**: Local LLM inference via Apple MLX
- [ ] **AI-02**: Fast model vs Quality model auto-switching based on context length
- [x] **AI-03**: Zero network calls for inference

### Context Pipeline (CTX)
- [x] **CTX-01**: Active text context via Accessibility API
- [ ] **CTX-02**: Surrounding screen text via Vision framework OCR
- [ ] **CTX-03**: Clipboard contents context
- [ ] **CTX-04**: Date/time awareness injection

### Menu & Settings (UI)
- [x] **UI-01**: Launch at login
- [x] **UI-02**: Menu bar icon with quick actions (disable, words saved, settings)
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
- **CORE-01** -> Phase 1
- **CORE-02** -> Phase 1
- **CORE-03** -> Phase 2
- **CORE-04** -> Phase 2
- **CORE-05** -> Phase 4
- **CORE-06** -> Phase 2
- **AI-01** -> Phase 2
- **AI-02** -> Phase 3
- **AI-03** -> Phase 2
- **CTX-01** -> Phase 2
- **CTX-02** -> Phase 3
- **CTX-03** -> Phase 3
- **CTX-04** -> Phase 3
- **UI-01** -> Phase 1
- **UI-02** -> Phase 1
- **UI-03** -> Phase 4
- **UI-04** -> Phase 4
- **PERS-01** -> Phase 4
- **PERS-02** -> Phase 5
- **PERS-03** -> Phase 5
- **PERS-04** -> Phase 4
- **APP-01** -> Phase 5
- **APP-02** -> Phase 5
