# Phase 6: Critical Bug Fixes — Research

## Overview
This phase addresses two critical bugs: the accessibility permission loop and the CGEvent text injection monitor bug.

## Issue 1: Accessibility Permission Loop
The current implementation of `AccessibilityMonitor.start()` calls `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` *every time* the app starts if permissions aren't granted. In an LSUIElement app, this can happen repeatedly without the user interacting, causing spam.
**Solution**:
Check `AXIsProcessTrusted()` directly for status. Only pass the prompt option if explicitly requested by a user action (e.g., clicking a "Grant Permission" button in Settings).

## Issue 2: CGEvent Monitor and Injection
The `CGEvent.tapCreate` function returns a valid tap, but `CFRunLoopAddSource(CFRunLoopGetCurrent(), ...)` is being called on an arbitrary queue depending on where `start()` was invoked.
**Solution**:
The run loop source must be added to the *main* run loop or a dedicated background thread run loop.
```swift
CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
```
Additionally, `kAXTrustedCheckOptionPrompt` check failure immediately returns, but if the app starts in the background and isn't trusted, it'll never register the tap.

## Validation Architecture
- Check that launching the app multiple times without accessibility permission does NOT trigger a macOS prompt automatically.
- Verify that Tab/Right Arrow events are successfully intercepted by `AccessibilityMonitor`.
