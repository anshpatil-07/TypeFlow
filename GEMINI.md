<!-- GSD:project-start source:PROJECT.md -->
## Project

**TypeFlow**

TypeFlow is a system-wide AI autocomplete macOS menu bar app that works in every Mac application. It monitors the active text field using Accessibility APIs and injects ghost-text completions inline, powered by a local LLM running entirely on-device via Apple's MLX framework. It provides contextual completions by combining active text, surrounding screen text via Vision OCR, and clipboard contents.

**Core Value:** Provide instantaneous (under 150ms), entirely on-device system-wide text completions that are context-aware and respect user privacy.

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
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
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



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
