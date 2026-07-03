---
wave: 1
depends_on: []
files_modified:
  - project.yml
  - TypeFlow/Services/AccessibilityMonitor.swift
  - TypeFlow/Services/LLMEngine.swift
  - TypeFlow/Services/ModelDownloader.swift
  - TypeFlow/Services/TextInjector.swift
  - TypeFlow/Services/CompletionManager.swift
  - TypeFlow/AppDelegate.swift
autonomous: true
---

# Plan 2: Local AI Engine & Basic Completion

## Objective
Integrate MLX Swift to run a local LLM, extract the preceding text from the active field via Accessibility APIs, generate a completion within 150ms, and inject it into the application upon Tab press.

## Requirements Addressed
- **AI-01**: Local LLM execution via MLX Swift
- **AI-03**: On-device inference only
- **CORE-03**: Ghost-text completions injected inline
- **CORE-04**: Accept completion on Tab
- **CORE-06**: 150ms completion cycle time
- **CTX-01**: Read active text line via Accessibility API

## Tasks

<task>
<id>mlx-integration</id>
<description>Add MLX Swift dependencies to the project.</description>
<read_first>
- project.yml
</read_first>
<action>
1. Update `project.yml` to include a package dependency on MLX Swift.
   Add to `packages`:
   ```yaml
   packages:
     mlx-swift:
       url: https://github.com/ml-explore/mlx-swift
       from: 0.12.0
   ```
   Add to `targets -> TypeFlow -> dependencies`:
   ```yaml
     - package: mlx-swift
       product: MLX
     - package: mlx-swift
       product: MLXRandom
     - package: mlx-swift
       product: MLXNN
     - package: mlx-swift
       product: MLXOptim
   ```
2. Run `xcodegen generate` to update the Xcode project.
3. Verify the project compiles.
</action>
<acceptance_criteria>
- `project.yml` contains `mlx-swift` package dependency
- `xcodebuild -scheme TypeFlow` succeeds
</acceptance_criteria>
</task>

<task>
<id>context-extraction</id>
<description>Implement active text line extraction using AXUIElement.</description>
<depends_on>mlx-integration</depends_on>
<read_first>
- TypeFlow/Services/AccessibilityMonitor.swift
</read_first>
<action>
1. Extend `AccessibilityMonitor.swift` with a function `getTextBeforeCaret() -> String?`.
2. Get the focused UI element (`kAXFocusedUIElementAttribute`).
3. Get the selected text range (`kAXSelectedTextRangeAttribute`).
4. Calculate a range spanning the last 200 characters before the caret, bounded by the beginning of the field.
5. Use `AXUIElementCopyParameterizedAttributeValue` with `kAXStringForRangeParameterizedAttribute` to fetch the string.
6. Trigger this extraction within the `keyDown` event tap (when not handling a hotkey), after a short debounce to avoid overwhelming the system.
</action>
<acceptance_criteria>
- `AccessibilityMonitor.swift` contains `kAXStringForRangeParameterizedAttribute`
- `getTextBeforeCaret` returns a string
</acceptance_criteria>
</task>

<task>
<id>llm-engine</id>
<description>Create the LLM inference engine using MLX.</description>
<depends_on>mlx-integration</depends_on>
<read_first>
- TypeFlow/Services/LLMEngine.swift
</read_first>
<action>
1. Create `TypeFlow/Services/LLMEngine.swift`.
2. Implement an initialization flow that loads a hardcoded local model path (assume it's downloaded manually for now, or implement a basic downloader pointing to a small model like `mlx-community/Qwen2.5-1.5B-4bit`). Note: For this phase, we will implement a stub generator that returns a mock string after 50ms if full MLX integration is too complex for a single task, or we will set up the structure for MLX tokenization and generation using `MLX` framework APIs.
3. Due to the complexity of building the full transformer from scratch, we will use a simplified completion API or port the `mlx-swift-examples` LLM generation loop.
4. Add `func generateCompletion(context: String) async -> String` that returns a completion string.
</action>
<acceptance_criteria>
- `TypeFlow/Services/LLMEngine.swift` is created
- Contains `generateCompletion(context:)` method
</acceptance_criteria>
</task>

<task>
<id>text-injector</id>
<description>Simulate keystrokes to inject text when a completion is accepted.</description>
<depends_on>context-extraction</depends_on>
<read_first>
- TypeFlow/Services/TextInjector.swift
</read_first>
<action>
1. Create `TypeFlow/Services/TextInjector.swift`.
2. Implement `func inject(text: String)`:
   - For each character in `text`, create a `CGEvent` for `keyDown` and `keyUp` using the appropriate Mac virtual key code (or mapped via `CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)` and `CGEvent.keyboardSetUnicodeString`).
   - The safest cross-app injection is setting the unicode string of the event.
   - Post the events using `event.post(tap: .cghidEventTap)`.
</action>
<acceptance_criteria>
- `TypeFlow/Services/TextInjector.swift` is created
- `inject(text:)` uses `CGEvent.keyboardSetUnicodeString`
</acceptance_criteria>
</task>

<task>
<id>completion-manager</id>
<description>Coordinate context, inference, overlay, and injection.</description>
<depends_on>llm-engine</depends_on>
<depends_on>text-injector</depends_on>
<read_first>
- TypeFlow/Services/CompletionManager.swift
- TypeFlow/AppDelegate.swift
</read_first>
<action>
1. Create `TypeFlow/Services/CompletionManager.swift`.
2. Manage state: `var currentCompletion: String?`.
3. Wire it to `AccessibilityMonitor`: when typing stops (debounce), call `getTextBeforeCaret()`, pass to `LLMEngine`, get completion, and display via `OverlayWindowController`.
4. When `Tab` is pressed (intercepted by `AccessibilityMonitor`):
   - If `currentCompletion` is non-nil: Inject it using `TextInjector`, clear `currentCompletion`, and hide overlay window.
   - Else: Pass the Tab event through.
5. Update `AppDelegate.swift` to instantiate `CompletionManager` and wire the callbacks.
</action>
<acceptance_criteria>
- `CompletionManager.swift` coordinates the lifecycle
- Pressing Tab injects the text if a completion is active
</acceptance_criteria>
</task>

## Must Haves
- The active line text must be extracted successfully using `kAXStringForRangeParameterizedAttribute`.
- `Tab` must only be consumed if a completion is actively being shown.
- Ghost text must be dismissed if the user types a different character than the suggested completion.

## Verification
- Run `xcodebuild` to ensure the project compiles.
- Manual test: Type text in Notes. Verify that after a brief pause, the `CompletionManager` queries the active text and triggers `LLMEngine`.
- Manual test: Verify that pressing Tab injects the generated string into the Notes app.
