# Stack Research

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
