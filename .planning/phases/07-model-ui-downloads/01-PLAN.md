---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/UI/SettingsView.swift
  - TypeFlow/Services/ModelManager.swift
requirements_addressed:
  - MODELS-01
  - MODELS-02
  - MODELS-03
autonomous: true
---

# Phase 7 Plan 1: Model Management UI & Downloads

## Objective
Implement a "Models" tab in `SettingsView` and a `ModelManager` to handle downloading and activating MLX models (Gemma 4 E2B and Qwen 2.5 1.5B).

## Tasks

```xml
<task>
  <read_first>
    - TypeFlow/Services/SettingsManager.swift
  </read_first>
  <action>
    Create a new file `TypeFlow/Services/ModelManager.swift`.
    Define `struct MLXModel: Identifiable` with properties `id`, `name`, `status` (enum: notDownloaded, downloading, downloaded), `progress` (Double), `isDownloaded`.
    Create `class ModelManager: ObservableObject` to manage models. Initialize it with two mock models: "Gemma 4 E2B" and "Qwen 2.5 1.5B".
    Add functions `downloadModel(id: String)` (simulating download using `Task.sleep` for UI purposes, updating `progress` from 0 to 1 over a few seconds) and `activateModel(id: String)`.
    In `activateModel`, update `SettingsManager.shared.activeModelId = id` (add this property to SettingsManager).
  </action>
  <acceptance_criteria>
    - `TypeFlow/Services/ModelManager.swift` contains `class ModelManager: ObservableObject`
    - `TypeFlow/Services/ModelManager.swift` contains `downloadModel(id: String)`
    - `TypeFlow/Services/ModelManager.swift` contains `activateModel(id: String)`
    - `SettingsManager.swift` contains `@Published var activeModelId`
  </acceptance_criteria>
</task>

<task>
  <read_first>
    - TypeFlow/UI/SettingsView.swift
  </read_first>
  <action>
    In `TypeFlow/UI/SettingsView.swift`, inject `@StateObject var modelManager = ModelManager()`.
    Add a new `Form` for the Models tab with `tabItem` `Label("Models", systemImage: "cpu")`.
    Inside the form, create a `List` or `ForEach` over `modelManager.models`.
    For each model, show its name, status/progress.
    Show a "Download" button if `notDownloaded`.
    Show a `ProgressView` if `downloading`.
    Show an "Activate" button if `downloaded` and not currently active.
    Show "Active" text if it is the currently active model.
  </action>
  <acceptance_criteria>
    - `TypeFlow/UI/SettingsView.swift` contains `Label("Models", systemImage: "cpu")`
    - `TypeFlow/UI/SettingsView.swift` contains `@StateObject var modelManager`
    - `TypeFlow/UI/SettingsView.swift` contains `ProgressView` for downloading models
  </acceptance_criteria>
</task>
```

## Verification
- Settings window displays the "Models" tab.
- User can click "Download", observe progress, and then "Activate" the model.
