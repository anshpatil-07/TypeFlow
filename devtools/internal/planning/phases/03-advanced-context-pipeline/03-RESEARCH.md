# Phase 3 Research: Advanced Context Pipeline

## Objective
Enhance the completion context by adding OCR-extracted screen text, clipboard contents, and the full active text field, and combine them into a comprehensive system prompt for the LLM.

## Context Sources

### 1. Clipboard Context (CTX-03)
- **API**: `NSPasteboard.general.string(forType: .string)`
- **Implementation**: Fast and synchronous. Can be pulled directly before generation. We should limit the size to prevent blowing out the context window (e.g., max 1000 characters).

### 2. Full Field Text (CTX-04)
- **API**: `AXUIElementCopyAttributeValue` with `kAXValueAttribute` or `kAXDocumentAttribute` (for some apps like Word/Pages).
- **Implementation**: Some apps return the full text in `kAXValueAttribute`. For large documents, this can be slow. It's better to fetch a large range around the caret using `kAXStringForRangeParameterizedAttribute` (e.g., 2000 chars before and 500 chars after).

### 3. Screen Text OCR (CTX-02)
- **API**: `CGWindowListCreateImage` for screenshot + Apple Vision Framework (`VNRecognizeTextRequest`).
- **Implementation**: 
  - Taking a full-screen screenshot and running OCR on every keystroke is too slow (can take 50-200ms depending on screen resolution).
  - *Strategy*: Run OCR in the background periodically (e.g., every 2-5 seconds) or only when the active window changes. Cache the OCR result.
  - Alternatively, take a screenshot of just the active window or the screen area around the caret.

## Prompt Construction (AI-02)
Combine all contexts into a structured prompt.
```text
You are a system-wide macOS autocomplete AI.
<clipboard>
{clipboard_text}
</clipboard>
<screen_context>
{ocr_text}
</screen_context>
<document>
{full_text}
</document>

Complete the following text seamlessly. Output ONLY the completion, no explanations.
Text: {active_line}
```

## Architecture
- `ClipboardContextManager`: Wraps `NSPasteboard`.
- `ScreenContextManager`: Runs periodic background OCR.
- `ContextAggregator`: Merges all sources.
- `PromptBuilder`: Formats the MLX prompt string.
