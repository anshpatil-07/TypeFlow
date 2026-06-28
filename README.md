# TypeFlow

**System-wide local AI typing assistant for macOS.**

TypeFlow is a native macOS menu bar application that provides intelligent, system-wide writing assistance. Powered by local LLMs (via llama.cpp and Apple's Metal framework) and leveraging the macOS Accessibility API (CGEventTap), TypeFlow works seamlessly across any application you type in.

> 🤖 **AI Agents & Contributors**: Please read [GEMINI.md](GEMINI.md) for the canonical architecture, prediction pipeline, and strict design constraints before modifying this repository.

## Features

- **Universal Autocomplete**: Get inline "ghost text" predictions as you type, in any macOS app.
- **Asynchronous Auto-Correct**: Non-blocking, atomic typo correction that doesn't interrupt your typing flow.
- **Abbreviation Expansion**: Fast, organic snippet injection (e.g., typing `yt` expands to `youtube`).
- **Rewrite Selection**: Use a hotkey-triggered panel to rewrite highlighted text (e.g., Shorter, Professional) with smart focus-restoration.
- **Adaptive Learning**: Continuously learns from your typing history to build a custom, personalized vocabulary. Your history is stored locally and securely encrypted.

## Privacy-First Architecture

TypeFlow is built with privacy as its foundational principle. All LLM inference happens entirely locally on your device using the Metal API. Your keystrokes, screen context, and typing history **never leave your device**.

### High-Level Architecture
TypeFlow bridges native macOS keystroke events with high-performance MLX inference via a precisely timed prediction pipeline:
1. **Accessibility (`CGEventTap` & `AXUIElement`)**: Monitors keystrokes and extracts the surrounding document context with near-zero latency.
2. **Prediction Orchestration**: Debounces rapid typing and manages overlapping generation requests.
3. **Context Assembly**: Fuses the active document with a real-time OCR screen snapshot and clipboard contents.
4. **Local Inference (`llama.cpp`)**: Reuses GPU KV-caches to evaluate completions under 150ms.
5. **Overlay UI**: Renders a non-interactive, pixel-perfect ghost text overlay ahead of the user's native cursor.

### Repository Map
* `TypeFlow/Services/`: Core orchestrators (`PredictionCoordinator`), queues (`PredictionWorker`), prompt assembly, and inference wrappers.
* `TypeFlow/UI/`: SwiftUI settings panels, menu bar app, and the transparent ghost text overlay.

* `TypeFlow/llama.cpp/`: The upstream inference engine submodule.

## Installation & Setup

### Prerequisites
- macOS 14+ (Apple Silicon highly recommended for Metal performance)
- Xcode 15+

### Build Instructions
1. Clone this repository.
2. Open `TypeFlow.xcodeproj` in Xcode.
3. Build and run the application.

### Permissions
TypeFlow requires specific permissions to function correctly:
- **Accessibility**: Required to read active text fields, monitor keystrokes, and inject ghost text/expansions.
- **Screen Recording**: Required for the local OCR vision system to understand your screen context.

You will be prompted to grant these permissions upon first launch.

### Model Setup
TypeFlow requires a local `.gguf` model file to run (e.g., Gemma 2B or Llama 3 8B).
1. Download a compatible `.gguf` model.
2. Place the model file in your `~/Documents/` folder (or configure the path in the app).

## Usage

TypeFlow lives in your macOS Menu Bar. Click the TypeFlow icon to access the following toggles and settings:

- **Quick Toggles**: Easily enable or disable Autocomplete, Auto-Correct, and Adaptive Learning on the fly.
- **Generation Settings**: Simplified sliders to control the LLM's output:
  - **Temperature**: Controls the creativity and randomness of the generated text.
  - **Max Length**: Limits the maximum number of tokens the AI can generate in a single response.
