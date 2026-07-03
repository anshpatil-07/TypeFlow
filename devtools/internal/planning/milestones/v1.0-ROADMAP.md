# Roadmap

## Phase 1: Core Injection & Foundation
**Goal**: Establish the Accessibility and UI foundations to detect keystrokes, locate the caret, and render an overlay window natively.
**Requirements**: CORE-01, CORE-02, UI-01, UI-02
**Success Criteria**:
- App launches at login and shows in the menu bar.
- App can detect when the user is typing in a standard text field (e.g., Notes app) and intercept the Tab key.
- A transparent overlay window accurately tracks the text caret position in at least 3 test apps.
**UI hint**: yes

## Phase 2: Local AI Engine & Basic Completion
**Goal**: Integrate MLX for on-device inference and inject simple ghost text using active text context.
**Requirements**: AI-01, AI-03, CORE-03, CORE-04, CORE-06, CTX-01
**Success Criteria**:
- MLX Swift loads a quantized local model without network access.
- Given the active text as context, model returns a completion in <150ms.
- The completion is rendered as ghost text in the overlay and injected into the active app upon pressing Tab.

## Phase 3: Advanced Context Pipeline
**Goal**: Expand context awareness to include Vision OCR (surrounding screen) and Clipboard.
**Requirements**: CTX-02, CTX-03, CTX-04, AI-02
**Success Criteria**:
- Vision framework OCR captures text around the active window without noticeable battery/CPU spike.
- Prompt dynamically includes clipboard content and screen text.
- System switches between fast and quality models based on the length of the accumulated context.

## Phase 4: Settings & Personalization
**Goal**: Build out the SwiftUI settings, custom instructions, and hotkeys.
**Requirements**: UI-03, UI-04, PERS-01, PERS-04, CORE-05
**Success Criteria**:
- Multi-pane settings window allows configuring delay, opacity, and custom hotkeys.
- User can define global and per-app AI instructions.
- Full line completions trigger via the user-configured hotkey.
**UI hint**: yes

## Phase 5: Tone, Snippets & App Overrides
**Goal**: Implement tone profiles, auto-snippets, and granular per-app controls.
**Requirements**: PERS-02, PERS-03, APP-01, APP-02
**Success Criteria**:
- LLM analyzes text to detect active tone and matches it in completions.
- Repeated phrases are surfaced as snippets that can be expanded with shortcodes.
- User can disable the app entirely for specific bundle IDs or browser domains.
