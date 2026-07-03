# Quick Task Summary: 260608-bnr

## What Was Done
- Modified `AccessibilityMonitor.swift`'s `getCurrentCaretRect()` function to prioritize WebKit and Chromium-specific caret tracking APIs (`AXSelectedTextMarkerRange` and `AXSelectedTextMarker`).
- Placed these specific text marker API checks before the standard macOS `kAXSelectedTextRangeAttribute` check.

## Why It Was Done
Web browsers like Chrome, Safari, and Zen support `kAXSelectedTextRangeAttribute` but often return the bounding box of the entire web view rather than the specific text caret. This caused the ghost text overlay to appear at the bottom left of the entire browser window instead of aligned with the typing cursor. By prioritizing the `AXTextMarker` APIs, we ensure precise caret position tracking in browsers while keeping the standard attributes as a fallback for native apps (Xcode, Notes, etc.).

## Verification
- Verified that the project builds cleanly.
- Code logically conforms to the requested changes.
