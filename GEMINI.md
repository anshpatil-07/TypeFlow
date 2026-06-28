<!-- GSD:project-start source:PROJECT.md -->
## Project

**TypeFlow**

TypeFlow is a system-wide AI autocomplete macOS menu bar app that works in every Mac application. It monitors the active text field using Accessibility APIs and injects ghost-text completions inline, powered by a local LLM running entirely on-device via Apple's MLX framework. It provides contextual completions by combining active text, surrounding screen text via Vision OCR, and clipboard contents.

**Core Value:** Provide instantaneous (under 150ms), entirely on-device system-wide text completions that are context-aware and respect user privacy.

### Project Purpose & Goals
* **What it is**: A native macOS typing assistant providing universal ghost text.
* **Problem it solves**: Brings high-speed, local LLM autocompletion to *any* native macOS application without requiring cloud APIs, preserving privacy and eliminating network latency.
* **Primary UX goals**: Ghost text must feel instantaneous and organic. It should appear instantly when typing pauses and gracefully disappear when the user diverges.
* **Performance goals**: Under 150ms total completion cycle time. Any slower, and the suggestion arrives after the user has already typed the next word.

### Constraints

- **Performance**: Under 150ms total completion cycle time — Crucial for natural typing experience; slower suggestions will be disruptive and rejected by users.
- **Privacy**: No network calls for inference — User context (screen, clipboard, typing) must never leave the device.
- **Platform**: Apple Silicon macOS 14+ only — Required for MLX and Vision APIs performance.
- **Tech Stack**: Swift and SwiftUI — Native performance and deep macOS integration.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Core Frameworks
- **Language**: Swift 6 (native performance, Safety)
- **UI**: SwiftUI (native settings/menus for macOS 14+)
- **Text Injection**: CoreGraphics (CGEvent) + Accessibility API (AXUIElement)
- **OCR/Vision**: Apple Vision Framework (VNRecognizeTextRequest)
- **AI Inference**: MLX Swift (mlx-swift) for Neural Engine execution
## Rationale
- MLX Swift provides the best Apple Silicon on-device performance compared to CoreML for dynamic LLMs.
- AXUIElement + CGEvent is the only reliable way to inject inline text and read active text without writing a custom input method (which is more complex).
- Apple Vision framework performs on-device OCR natively with very low latency.
## Avoid
- Electron/Tauri: Memory overhead too high for an always-on background tool.
- Cloud APIs (OpenAI/Anthropic): Violates privacy constraints and 150ms latency target.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions & Design Principles

The following principles should guide future changes to the repository:
* **Preserve completion quality**: Always measure whether a change to prompt construction or context gathering improves or degrades the LLM output. 
* **Optimize perceived responsiveness**: Even if inference is fast, the scheduling and rendering pipelines must never block the main thread or queue behind stale completions.
* **Prefer architectural understanding over heuristic fixes**: Understand the `PredictionWorker` queues, the `LLMEngine` KV-cache, and `evaluateKeystroke` transitions before band-aiding issues.
* **Make isolated, measurable changes**: Do one logical improvement at a time (e.g. optimizing debouncing, OR optimizing overlap removal, never both).
* **Avoid unrelated refactors**: Do not clean up code or restructure pipelines if you are tasked with fixing a specific bug. 

### Immutable AI Contributor Laws
If you are an AI agent attempting to modify this codebase, you must adhere to these absolute constraints:
1. **DO NOT TOUCH THE EVENT TAP RETURN**: The `CGEventTap` MUST return immediately. Do not block the tap or introduce synchronous latency.
2. **DO NOT TOUCH THE OVERLAP STRIPPER**: Do not modify `stripOverlap` to filter out underscores or other critical boundary characters.
3. **DO NOT ALTER MLX CACHE LOGIC**: Token Healing explicitly bypasses the KV Cache. Do not append partial tokens to cached states inside the LLM engine.
4. **DO NOT ADD NEW RATE LIMITERS**: No artificial `Task.sleep` suspensions to the `CompletionManager` pipeline. Rely on the existing `debounceTask`.
5. **DO NOT MESS WITH GHOST TEXT INJECTION**: Leave the word-by-word Tab extraction and CGEvent text injection logic exactly as it is.


<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture & Prediction Pipeline

TypeFlow operates heavily on asynchronous queues to bridge synchronous user keystrokes with heavy MLX inference.

### High-Level Subsystems

* **Accessibility (`AccessibilityMonitor`)**: 
  * *Responsibility*: Listens for keystrokes via `CGEventTap` and polls the active text field via `AXUIElement`.
  * *Inputs*: macOS native input events.
  * *Outputs*: A localized `bufferSnapshot` and triggers for `EditorEventBus`.
* **PredictionCoordinator** (`@MainActor`): 
  * *Responsibility*: Receives events, evaluates keystroke transitions (`.noGhostText`, `.invalidated`, `.matchedAndAdvanced`), manages the 150ms debounce timer, and updates the Ghost Text Overlay. 
  * *Design Decision*: Ensures "Latest Generation Wins" by tracking `generationIDCounter`. It explicitly cancels stale generations if the user diverges.
* **PredictionWorker** (`actor`): 
  * *Responsibility*: A serial execution queue for LLM generations. Prevents the GPU/Neural Engine from running concurrent inferences. 
  * *Design Decision*: Must clear its `activeTask` explicitly via cancellation to avoid head-of-line blocking.
* **PromptBuilder**: 
  * *Responsibility*: Assembles the 500-token prompt (System Instructions, OCR Screen Context, Clipboard, and current text).
  * *Design Decision*: Uses a frozen prefix for context (OCR/Clipboard) to maximize KV-cache reuse, appending only the typed suffix on every keystroke.
* **LLMEngine (`TypeFlowLlamaWrapper`)**: 
  * *Responsibility*: Executes the LLM inference loop using `llama.cpp` or MLX.
  * *Design Decision*: Implements Smart Prompt Caching. It calculates `matchingLength` between the new prompt and previous prompt, dropping only the diverged tail from the GPU's KV cache.
* **CompletionManager & OverlayWindowController**:
  * *Responsibility*: Renders the final sanitized string into an invisible, non-interactive overlay perfectly aligned with the user's native text caret.

### The Prediction Pipeline Lifecycle

1. **Keystroke**: User types a character. `CGEventTap` intercepts it.
2. **Accessibility**: Updates `liveBuffer` and emits an event to `PredictionCoordinator`.
3. **PredictionCoordinator**: Evaluates the keystroke. If no ghost text matches, it waits for the 150ms `debounceTask`. Once expired, it increments the generation ID and submits to `PredictionWorker`.
4. **PredictionWorker**: Enqueues the request. If the LLM is idle, it starts immediately. If busy, it waits (unless properly cancelled).
5. **PromptBuilder**: Rebuilds the final prompt string, combining the massive OCR screen dump and the 10-token active typing line.
6. **LLMEngine**: Tokenizes the prompt, natively reuses ~490 tokens from the KV-cache, and evaluates only the newly typed suffix. Begins streaming tokens.
7. **Ghost Text Overlay**: `PredictionCoordinator` receives the tokens, sanitizes them, verifies overlap, and sends them to the SwiftUI overlay to be drawn ahead of the caret.
8. **Tab Acceptance**: If the user presses Tab, `CompletionManager` accepts the suggestion and injects it via `CGEvent` text insertion.

### Known Architectural Constraints
* **Actor Boundaries**: `PredictionCoordinator` strictly owns the main thread (UI). `PredictionWorker` strictly owns the serialization queue. Crossing these boundaries incorrectly introduces severe latency.
* **Cancellation Model**: The LLM engine is a C-binding loop. Cancelling the Swift `Task` does not instantly halt the hardware; it stops on the *next token decode*.
* **Prompt Signal-to-Noise**: The OCR dump (~400 tokens) heavily dominates the prompt compared to the current line (~10 tokens).

### Current Development Priorities
* Replicate the UX shown in reference videos exactly.
* Ensure `.noGhostText` continuous typing aggressively cancels stale generations to reduce perceived latency.
* Prevent the LLM from outputting conversational AI text or generic punctuation due to OCR hallucination.
* Maintain completely local Apple Silicon inference.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

### Repository Map
* `TypeFlow/Services/`: Core business logic (`PredictionCoordinator`, `PredictionWorker`, `PromptBuilder`, `LLMEngine`, `AccessibilityMonitor`).
* `TypeFlow/UI/`: SwiftUI overlays, settings views, and menu bar components.
* `TypeFlow/llama.cpp/`: The upstream C++ inference engine submodule. Do not modify directly.


<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
