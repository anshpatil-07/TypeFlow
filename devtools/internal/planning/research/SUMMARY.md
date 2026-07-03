# Research Synthesis

## Stack Additions
- **`URLSession` / `Combine`**: For background downloading of MLX models.
- **`AppIntents` / `AXIsProcessTrusted`**: To reliably check accessibility permissions without triggering loops.

## Feature Table Stakes
- **Model Downloads UI**: Must show download progress (%), file size, and cancellation capability. Once downloaded, must show an "Activate" button.
- **Accessibility Status**: The UI should show the current status of the Accessibility permission and guide the user to System Settings if not granted.

## Watch Out For (Pitfalls)
- **Accessibility Permission Loop**: Calling `AXIsProcessTrustedWithOptions` with `prompt: true` on every launch will spam the user. It must be called with `prompt: false` initially to check status, and only prompt when explicitly requested or required.
- **Ghost Text Injection**: `CGEvent` text injection requires standard privileges. Ensure the accessibility monitor `runLoopSource` is actually added to the correct thread's run loop.
- **App Sandbox limitations**: Background model downloads in macOS require appropriate entitlements (e.g., `com.apple.security.network.client`) if downloading from HuggingFace.

## Architectural Impact
- A `ModelDownloadManager` will be needed to handle large file background downloads using `URLSessionDownloadTask`.
- Accessibility checks need a centralized `PermissionsManager` to track process trust state.
