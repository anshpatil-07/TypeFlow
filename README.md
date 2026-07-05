# TypeFlow

**Instantaneous, system-wide on-device AI typing assistant for macOS.**

TypeFlow is a native macOS menu bar application that monitors active text fields using Apple's Accessibility APIs and injects contextual ghost-text completions inline. Powered by local LLMs running entirely on Apple Silicon via MLX and Metal, TypeFlow fuses your active typing line with real-time Vision OCR screen snapshots and clipboard contents—delivering instant, privacy-preserving autocomplete across any macOS application.

> [!NOTE]
> **Pre-1.0 Status**: TypeFlow v0.8 is an active pre-1.0 project under continuous refinement. While core autocompletion, prefix consumption, and KV-cache reuse are highly functional, it is actively evolving toward a 150ms latency target and flawless visual stability across complex rich-text editors.

> [!IMPORTANT]
> **AI Agents & Contributors**: Before modifying this repository, read [GEMINI.md](GEMINI.md) for the canonical architecture, prediction pipeline lifecycle, immutable AI contributor laws, and strict design constraints.

---

## Demo

<p align="center">
</p>

https://github.com/user-attachments/assets/ebc79d29-ca34-42c3-aac4-66438a382eff

---

## Key Features

- **Universal System-Wide Ghost Text**: Inline autocompletion that works seamlessly in Safari, Xcode, TextEdit, Notes, Mail, and other native macOS applications without custom input methods or browser extensions.
- **100% On-Device & Privacy-First**: Zero cloud calls or network dependency. All document context, screen OCR, clipboard reads, and LLM inferences execute locally on your Apple Silicon Neural Engine and GPU.
- **Sub-150ms Latency Pipeline**: Highly optimized asynchronous architecture designed to deliver suggestions faster than human typing pauses, preventing cognitive disruption.
- **Smart Prompt Caching & KV-Cache Reuse**: Retains ~490 tokens of background context (OCR and clipboard) in GPU memory, evaluating only the newly typed suffix on every keystroke.
- **Advanced Token Healing**: Seamlessly handles mid-word pauses without generating redundant prefixes or breaking token boundaries.
- **Prefix Consumption & Overlap Stripping**: Dynamically consumes typed prefixes against active ghost text without triggering unnecessary re-generation, maintaining visual stability.

---

## The Prediction Pipeline

When you type in any native application, TypeFlow executes a precisely timed asynchronous cycle:

```
[Keystroke Event] ──> CGEventTap (Non-blocking) ──> AccessibilityMonitor
                                                            │
                                                            ▼
[Overlay Injection] <── Overlap Stripper <── LLM Engine <── PredictionCoordinator
    (SwiftUI)               & Sanitizer      (KV-Cache)     (@MainActor Debounce)
```

1. **Keystroke Interception**: `CGEventTap` captures typing events with zero synchronous blocking, while `AXUIElement` polls the active text field buffer.
2. **Debounced Evaluation**: `PredictionCoordinator` evaluates keystroke transitions (`.noGhostText`, `.invalidated`, `.matchedAndAdvanced`). If typing pauses, it triggers a 150ms debounce timer and cancels stale generations.
3. **Context Assembly**: `PromptBuilder` combines the static background context (real-time Apple Vision OCR screen snapshot + clipboard contents) with the live 10-token active line.
4. **Local Neural Inference**: `PredictionWorker` serializes execution to `LLMEngine` (`TypeFlowLlamaWrapper`). The engine drops only diverged tail tokens from the GPU KV-cache and streams new completion tokens.
5. **Overlay Rendering & Acceptance**: The generated string is sanitized, stripped of prefix overlap, and sent to an invisible, non-interactive SwiftUI overlay perfectly aligned ahead of your caret. Pressing **Tab** accepts the suggestion via atomic `CGEvent` text insertion.

---

## Architecture & Subsystems

TypeFlow relies on strict concurrency boundaries to bridge synchronous macOS UI events with heavy machine learning inference:

| Subsystem | Actor / Thread | Primary Responsibility |
|---|---|---|
| `AccessibilityMonitor` | Background / RunLoop | Intercepts keystrokes and extracts localized text buffer snapshots. |
| `PredictionCoordinator` | `@MainActor` | Manages UI state, debounce timers, generation IDs, and stale task cancellation. |
| `PredictionWorker` | `actor` | Serial execution queue preventing GPU/Neural Engine resource contention. |
| `PromptBuilder` | Synchronous | Formats multi-modal context (OCR, clipboard, active line) with frozen prefix structures. |
| `LLMEngine` | C-Binding Loop | Wraps `llama.cpp` / Metal execution with prefix matching and token healing. |
| `CompletionManager` | `@MainActor` | Orchestrates Tab acceptance, word-by-word stepping, and text injection. |

---

## Privacy & Security

TypeFlow is engineered around total data sovereignty:
- **No Network Permissions**: The application does not make HTTP requests, telemetry calls, or cloud API connections.
- **On-Device Vision OCR**: Screen context is extracted using Apple's native `Vision.framework` (`VNRecognizeTextRequest`) completely within OS memory.
- **Memory Safety**: Buffer snapshots and OCR dumps are ephemeral and discarded immediately after generation cycles.

---

## Installation & Setup

### Prerequisites
- **macOS**: macOS 14.0 or later (Apple Silicon M1/M2/M3/M4 required for Metal/MLX hardware acceleration).
- **Xcode**: Xcode 15.0+ (for building from source).
- **Model File**: TypeFlow currently uses **`Qwen2.5-Coder-1.5B-Instruct`** quantized to 4-bit (`Qwen2.5-Coder-1.5B.Q4_K_M.gguf`) as its canonical model, leveraging native Fill-In-the-Middle (FIM) token support (`<|fim_prefix|>`, `<|fim_suffix|>`, `<|fim_middle|>`). Other GGUF models (such as Gemma-2B causal models) are also supported via profile selection.

### Build Instructions
1. Clone the repository:
   ```bash
   git clone --recursive https://github.com/your-username/cotyper.git
   cd cotyper
   ```
2. Open the project in Xcode:
   ```bash
   open TypeFlow.xcodeproj
   ```
3. Select the **TypeFlow** scheme and build/run (`Cmd + R`).

### System Permissions
Upon initial launch, macOS will prompt for required system permissions:
1. **Accessibility**: Required to monitor keystrokes via `CGEventTap` and read active text caret positions via `AXUIElement`.
   - *System Settings ──> Privacy & Security ──> Accessibility ──> Enable TypeFlow*
2. **Screen Recording**: Required for Apple Vision OCR to read surrounding screen text for contextual grounding.
   - *System Settings ──> Privacy & Security ──> Screen & System Audio Recording ──> Enable TypeFlow*

### Configuring the LLM
1. Download the canonical **`Qwen2.5-Coder-1.5B.Q4_K_M.gguf`** model file (or another compatible GGUF model).
2. Place the model file in `~/Documents/` (or configure its location via the TypeFlow menu bar settings icon or launch arguments).
3. Once loaded, TypeFlow automatically selects the `qwenCoderFIM` profile, initializes the GPU KV-cache, and displays a ready status in the menu bar.

---

## Development & Diagnostics (`devtools/`)

TypeFlow v0.8 includes an extensive, self-contained suite of diagnostic tools, automated benchmarks, and UI probes located in the `devtools/` directory. These tools ensure zero regression in latency, memory stability, or completion accuracy.

```
devtools/
├── benchmarks/     # End-to-end automated benchmarks & harness shell scripts
├── probes/         # Isolated diagnostic scripts & UI/geometry verification probes
├── scripts/        # Utilities for log auditing, latency extraction & stress typing
├── tests/          # Standalone core verification tests (test_overlap.swift, etc.)
├── reports/        # Generated evaluation logs, jsonl results & markdown reports
└── scratch/        # Experimental code & temporary testing scratchpad
```

### Running Core Verification Tests
Execute standalone unit verification suites directly from the repository root:
```bash
swift devtools/tests/test_promptbuilder.swift
swift devtools/tests/test_overlap.swift
swift devtools/tests/test_mem.swift
swift devtools/tests/test_page_direct_matcher.swift
```

### Running Core Benchmarks
You can execute automated evaluation suites directly from the terminal without polluting the root workspace:

- **Safari Product & Integration Benchmark**:
  ```bash
  ./devtools/benchmarks/run_safari_product_benchmark.sh
  ```
- **Continuous Ghost Visibility & Stability Benchmark**:
  ```bash
  ./devtools/benchmarks/run_continuous_visibility_benchmark.sh
  ```
- **Acceptance Behavior & Latency Analysis**:
  ```bash
  ./devtools/benchmarks/run_acceptance_behavior_benchmark.sh
  ./devtools/benchmarks/run_acceptance_latency_benchmark.sh
  ```
- **Prefix Consumption Suite**:
  ```bash
  ./devtools/benchmarks/run_prefix_consumption_benchmark.sh
  ```

All benchmark runs automatically output structured JSON/JSONL results and human-readable Markdown summaries into `devtools/reports/benchmark_artifacts/`.

---

## Repository Map

- `TypeFlow/`: Primary macOS application source code.
  - `Services/`: Core business logic (`PredictionCoordinator`, `PredictionWorker`, `PromptBuilder`, `LLMEngine`, `AccessibilityMonitor`).
  - `UI/`: SwiftUI settings panels, menu bar controls, and transparent overlay windows.
  - `Models/`: Data structures for buffer snapshots, editor events, and completion states.
- `TypeFlow/llama.cpp/`: Upstream C++ inference engine submodule.
- `devtools/`: Developer tooling, automated test harnesses, diagnostic scripts, and benchmark reporting.
- `tests/`: Unit test fixtures and regression test suites.
- `devtools/tests/`: Standalone core verification tests (`test_promptbuilder.swift`, `test_overlap.swift`, `test_mem.swift`, `test_page_direct_matcher.swift`).

---

## License

This project is licensed under the terms of the [MIT License](LICENSE). See the `LICENSE` file for details.
