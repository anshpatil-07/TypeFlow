---
wave: 1
depends_on: []
files_modified:
  - TypeFlow/Services/AccessibilityMonitor.swift
requirements_addressed:
  - BUGS-01
  - BUGS-02
autonomous: true
---

# Phase 6 Plan 1: Fix Accessibility & CGEvent Monitor

## Objective
Fix the accessibility permission prompt loop that occurs on launch when permission is not granted.
Ensure that the `CGEvent` run loop source is added to `CFRunLoopGetMain()` instead of `CFRunLoopGetCurrent()` so that key interception works reliably regardless of which thread invokes `start()`.

## Tasks

```xml
<task>
  <read_first>
    - TypeFlow/Services/AccessibilityMonitor.swift
  </read_first>
  <action>
    In `TypeFlow/Services/AccessibilityMonitor.swift`, locate the `start()` function.
    Modify the initial accessibility check:
    ```swift
    if !AXIsProcessTrusted() {
        print("Accessibility permissions not granted. Waiting for user to grant them in Settings.")
        return
    }
    ```
    Remove the `AXIsProcessTrustedWithOptions` call with `prompt: true` from `start()`.
    
    Add a new method for manual prompting:
    ```swift
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    ```
  </action>
  <acceptance_criteria>
    - `AccessibilityMonitor.swift` contains `func requestPermission()`
    - `AccessibilityMonitor.swift` inside `start()` contains `if !AXIsProcessTrusted() {` and does NOT contain `AXIsProcessTrustedWithOptions`
  </acceptance_criteria>
</task>

<task>
  <read_first>
    - TypeFlow/Services/AccessibilityMonitor.swift
  </read_first>
  <action>
    In `TypeFlow/Services/AccessibilityMonitor.swift`, locate the run loop attachment code inside `start()` (around line 55).
    Change:
    ```swift
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    ```
    To:
    ```swift
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    ```
    This guarantees the tap is processed on the main run loop.
  </action>
  <acceptance_criteria>
    - `AccessibilityMonitor.swift` contains `CFRunLoopAddSource(CFRunLoopGetMain()`
  </acceptance_criteria>
</task>
```

## Verification
- Running the app without accessibility permissions does not spam system prompts.
- `grep "CFRunLoopAddSource(CFRunLoopGetMain()" TypeFlow/Services/AccessibilityMonitor.swift` returns a match.
