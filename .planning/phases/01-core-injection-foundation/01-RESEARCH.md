# Phase 1 Research: Core Injection & Foundation

## Objective
Determine the best technical approaches for Accessibility APIs (AXUIElement), Event Taps (CGEvent), and overlay window positioning.

## Key Challenges
1. **Keystroke Interception**: Need to listen to keys without running a full custom input method (IME).
   - *Solution*: Use `CGEvent.tapCreate` at the `cghidEventTap` or `cgsessionEventTap` level. Intercepting Tab means we return `nil` from the tap callback when we want to consume it.
2. **Caret Tracking**: Finding the exact screen coordinates of the text caret in any app.
   - *Solution*: Use `AXUIElement` for the focused element. Query `AXSelectedTextRange` to get the range, then `AXBoundsForRange` to get the CGRect of the caret on screen. Some apps (Electron) may not support this natively.
3. **Overlay Window**: Rendering ghost text that looks like it belongs to the target app.
   - *Solution*: Create a borderless, transparent `NSWindow` with `level = .floating`. Position it exactly at the caret's bounds.
4. **App Sandbox & Permissions**:
   - *Solution*: Requires Accessibility permissions. The app must prompt the user to enable this in System Settings -> Privacy & Security -> Accessibility.

## Implementation Details
- **UI-01**: `SMAppService.mainApp.register()` can be used to launch at login on macOS 13+.
- **UI-02**: SwiftUI `MenuBarExtra` or `NSStatusItem` for the menu bar icon.

## Validation Architecture
- Check if AX API returns valid bounds.
- Verify CGEvent tap properly blocks the Tab key without side effects.
