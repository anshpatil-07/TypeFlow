---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/UI/SettingsView.swift
requirements_addressed:
  - MODELS-01
autonomous: true
---

# Phase 7 Plan 2: Gap Fix - Models Tab Rendering

## Objective
Fix the UI bug where the Models tab is entirely missing from the Settings window because of SwiftUI layout issues on macOS caused by nesting `List` inside `Form`.

## Tasks

```xml
<task>
  <read_first>
    - TypeFlow/UI/SettingsView.swift
  </read_first>
  <action>
    In `TypeFlow/UI/SettingsView.swift`, locate the "Models Tab" section.
    Change `Form { List(modelManager.models) { ... } }` to `Form { ForEach(modelManager.models) { ... } }`.
    `ForEach` works cleanly inside a `Form` without triggering the nested scroll view layout collapse that `List` does.
  </action>
  <acceptance_criteria>
    - `TypeFlow/UI/SettingsView.swift` does not contain `List(modelManager.models)`
    - `TypeFlow/UI/SettingsView.swift` uses `ForEach(modelManager.models)` inside the `Form` for the Models tab
  </acceptance_criteria>
</task>
```

## Verification
- Running the app and opening Settings window (`Cmd+,`) displays the Models tab properly.
- The layout is visible and no longer collapses to 0 height.
