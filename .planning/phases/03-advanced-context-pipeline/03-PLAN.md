---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/ClipboardContextManager.swift
  - TypeFlow/Services/ScreenContextManager.swift
  - TypeFlow/Services/AccessibilityMonitor.swift
  - TypeFlow/Services/ContextAggregator.swift
  - TypeFlow/Services/PromptBuilder.swift
  - TypeFlow/Services/CompletionManager.swift
autonomous: true
---

# Plan 3: Advanced Context Pipeline

## Objective
Combine multiple context sources (OCR, clipboard, full AX field text) and pipe them into the LLM system prompt to provide highly relevant context for completions.

## Requirements Addressed
- **CTX-02**: Screen text context via Vision Framework OCR on periodic screenshots
- **CTX-03**: Clipboard content context
- **CTX-04**: Active field full text
- **AI-02**: System prompt construction incorporating all context sources

## Tasks

<task>
<id>clipboard-context</id>
<description>Implement clipboard content extraction.</description>
<read_first>
- TypeFlow/Services/ClipboardContextManager.swift
</read_first>
<action>
1. Create `TypeFlow/Services/ClipboardContextManager.swift`.
2. Implement `func getClipboardText() -> String?`.
3. Read from `NSPasteboard.general.string(forType: .string)`.
4. Truncate the output to a maximum of 1000 characters to prevent prompt bloat.
</action>
<acceptance_criteria>
- `ClipboardContextManager.swift` is created
- `getClipboardText()` returns truncated string
</acceptance_criteria>
</task>

<task>
<id>screen-context-ocr</id>
<description>Implement periodic screen OCR using Vision Framework.</description>
<read_first>
- TypeFlow/Services/ScreenContextManager.swift
</read_first>
<action>
1. Create `TypeFlow/Services/ScreenContextManager.swift`.
2. Import `Vision` and `CoreImage`.
3. Implement a timer that fires every 5 seconds.
4. On fire:
   - Capture the main screen using `CGWindowListCreateImage(.bounds(NSScreen.main!.frame), .optionOnScreenOnly, kCGNullWindowID, .nominalResolution)`.
   - Create a `VNImageRequestHandler` and perform a `VNRecognizeTextRequest`.
   - Store the recognized text in a thread-safe property `var latestScreenText: String`.
5. Truncate the cached text to ~2000 characters.
</action>
<acceptance_criteria>
- `ScreenContextManager.swift` created
- Uses `VNRecognizeTextRequest`
- Periodically updates `latestScreenText`
</acceptance_criteria>
</task>

<task>
<id>full-field-context</id>
<description>Extract the full active field text using Accessibility API.</description>
<depends_on>clipboard-context</depends_on>
<read_first>
- TypeFlow/Services/AccessibilityMonitor.swift
</read_first>
<action>
1. Extend `AccessibilityMonitor.swift` with `func getFullFieldText() -> String?`.
2. Query `kAXValueAttribute` on the focused `AXUIElement`.
3. If that fails or returns empty, fallback to querying a large range using `kAXStringForRangeParameterizedAttribute` (e.g., 2000 chars before and 2000 after the caret).
4. Return the aggregated text.
</action>
<acceptance_criteria>
- `getFullFieldText()` is implemented and returns a String
</acceptance_criteria>
</task>

<task>
<id>context-aggregation-prompt</id>
<description>Aggregate all context sources and build the final system prompt.</description>
<depends_on>full-field-context</depends_on>
<depends_on>screen-context-ocr</depends_on>
<read_first>
- TypeFlow/Services/ContextAggregator.swift
- TypeFlow/Services/PromptBuilder.swift
- TypeFlow/Services/CompletionManager.swift
</read_first>
<action>
1. Create `TypeFlow/Services/ContextAggregator.swift` to gather:
   - Clipboard text
   - Screen text
   - Full field text
   - Active line text
2. Create `TypeFlow/Services/PromptBuilder.swift`:
   - Implement `func buildPrompt(context: AggregatedContext) -> String`.
   - Format the prompt using XML-like tags for sections (`<clipboard>`, `<screen>`, `<document>`, etc.) as defined in research.
3. Update `CompletionManager.swift` to use `ContextAggregator` instead of just `getTextBeforeCaret()`, and pass the fully built prompt to `LLMEngine`.
</action>
<acceptance_criteria>
- `ContextAggregator.swift` correctly fetches from all 3 sources
- `PromptBuilder.swift` formats the string correctly
- `CompletionManager.swift` integration is complete
</acceptance_criteria>
</task>

## Must Haves
- OCR must run in the background and not block the main thread.
- Context size must be bounded (truncated) so the LLM context window is not exceeded.
- The prompt must clearly distinguish between the active text to complete and the background context.

## Verification
- Run `xcodebuild` to ensure the project compiles.
- Manual test: Copy some text, open an app, and verify that the context string sent to `LLMEngine` includes the clipboard text.
