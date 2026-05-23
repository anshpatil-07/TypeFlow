# Phase 2 Research: Local AI Engine & Basic Completion

## Objective
Integrate Apple's MLX Swift for on-device LLM inference, extract the current line of text using Accessibility APIs, and inject the completion into the target application when Tab is pressed.

## Key Challenges
1. **MLX Swift Integration**: 
   - *Solution*: Add `https://github.com/ml-explore/mlx-swift` as a Swift Package dependency. We will also need `mlx-swift-examples` or similar tokenizer/generation code to run a model like Qwen 2.5 1.5B.
2. **Model Management**:
   - *Solution*: Models are too large to bundle. Implement a downloader that fetches the model from Hugging Face to `~/Library/Application Support/TypeFlow/Models` on first launch.
3. **Active Line Extraction (CTX-01)**:
   - *Solution*: Use `kAXSelectedTextRangeAttribute` to get the caret position, then use `kAXStringForRangeParameterizedAttribute` to fetch the preceding text on the current line (or up to a reasonable limit, e.g., 200 chars).
4. **Text Injection (CORE-03 & CORE-04)**:
   - *Solution*: When Tab is pressed and a ghost text completion is active:
     1. Consume the Tab event (return `nil` from CGEvent tap).
     2. Dispatch a series of `CGEvent` keystrokes for each character in the completion, or use `AXUIElementSetAttributeValue` (less reliable across apps) or Pasteboard + Cmd+V (faster for long strings, but destroys clipboard history). The safest universal way is `CGEvent` keyboard emulation for short strings or Pasteboard backup/restore for longer strings. We'll start with `CGEvent` keyboard emulation.
5. **Latency (CORE-06)**:
   - *Solution*: Keep the model loaded in memory. Generate only a few tokens (e.g., up to the next space or newline). Use MLX's high-performance generation loop.

## Architecture
- `LLMEngine`: Singleton managing MLX model loading, tokenization, and generation.
- `ContextExtractor`: Uses AXUIElement to get the text before the caret.
- `CompletionManager`: Coordinates `ContextExtractor`, `LLMEngine`, and `OverlayWindowController`.
- `TextInjector`: Uses `CGEvent` to simulate typing the accepted completion.

## UI Considerations
- An onboarding screen or Settings tab to show model download progress.

## Validation Strategy
- Verify model loads in MLX Swift without crashing.
- Verify active text is accurately read from standard apps (Notes, TextEdit).
- Verify Tab injection correctly outputs the generated string.
