# Project Retrospective

## Milestone: v1.0 — MVP

**Shipped:** 2026-05-23
**Phases:** 5 | **Plans:** 5

### What Was Built
1. Established Accessibility foundation for native caret text tracking.
2. Integrated MLX for sub-150ms on-device LLM inference.
3. Created an advanced context pipeline using Apple Vision OCR.
4. Built a multi-pane SwiftUI Settings UI for custom instructions and hotkeys.
5. Implemented dynamic tone profiles and per-app config overrides.

### What Worked
- Leveraging Apple's native APIs (`AXUIElement`, `Vision`, `MLX`) drastically improved performance and allowed us to easily meet the strict `<150ms` latency requirement.
- The use of wave-based execution and clearly separated phases prevented context pollution.

### What Was Inefficient
- Settings window opening mechanism failed due to the app being an `LSUIElement`. We caught this in final UAT and had to hotfix `MenuBarManager` to instantiate the `NSWindow` manually.

### Patterns Established
- SwiftUI Views for Settings and macOS 14+ idioms.
- Using `AppStorage` to cleanly handle persistence without complex local data stores.
- Direct MLX injection from standard strings, avoiding intermediate parsing steps.

### Key Lessons
- Background apps (`LSUIElement`) have unexpected limitations regarding standard SwiftUI Scenes. `Settings` scenes often fail to launch without a main menu. Always test UI elements inside the actual runtime profile, not just as standalone previews.

## Cross-Milestone Trends

| Milestone | Velocity | Bug Rate | UAT Issues |
|-----------|----------|----------|------------|
| v1.0 MVP  | Fast     | Low      | 1          |
