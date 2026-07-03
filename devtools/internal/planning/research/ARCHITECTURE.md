# Architecture Research

## Component Boundaries
1. **Input Monitor Layer**: Accessibility observers (AXObserver) and Event Tap (CGEvent) for keystrokes.
2. **Context Aggregator**: Merges AX text context, clipboard (NSPasteboard), and periodic screenshots (CGWindowListCreateImage) -> Vision OCR.
3. **Inference Engine**: MLX Swift wrapper loading quantized weights (Qwen 1.5B/Gemma 4).
4. **UI Overlay**: Transparent borderless NSWindow pinned to text caret coordinates (AXTextMarker/AXSelectedTextRange) to render ghost text.
5. **Settings & State**: SwiftUI settings window + UserDefaults/Keychain.

## Data Flow
Keystroke -> Event Tap blocks/passes -> Context Aggregator -> Prompt Builder -> MLX Inference -> UI Overlay -> Tab key -> Injection via CGEvent.

## Build Order Implications
1. Permissions & Accessibility boilerplate
2. Context Aggregation (Text, OCR, Clipboard)
3. Local Inference setup with MLX
4. UI Overlay and Injection logic
