# Phase 7: Model UI & Downloads — Research

## Overview
Phase 7 adds a Model Management UI to `SettingsView` and handles background downloads for MLX models (Gemma 4 E2B, Qwen 2.5 1.5B) along with model activation capabilities.

## UI Integration
- Add a new tab `Label("Models", systemImage: "cpu")` to `SettingsView.swift`.
- The Models view needs to display a list of supported models.
- For each model, show its status: "Not Downloaded", "Downloading (X%)", "Downloaded", "Active".
- Buttons for each state: "Download", "Cancel", "Activate".

## State Management
We need a new service `ModelManager: ObservableObject` to handle:
- List of available models (e.g., `[MLXModel]`).
- Download state and progress (tracked via `URLSessionDownloadDelegate`).
- Active model selection.

## Implementation Details
Since MLX requires multiple files (weights, tokenizers, configs), a `URLSession` must download these from HuggingFace to a dedicated local directory (e.g., `~/Library/Application Support/TypeFlow/Models/`).
For this phase, a simplified download simulation or a basic single-file download can be used as a placeholder if actual MLX swift integration is deferred. 

## Validation Architecture
- Open Settings -> Models tab.
- Click "Download" on Gemma 4 E2B.
- Verify progress indicator updates.
- Verify "Activate" button becomes available.
- Verify clicking "Activate" sets it as the active model in `SettingsManager`.
