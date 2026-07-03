# Discussion Log: Phase 16

**Phase:** Performance & Battery Emergency
**Date:** 2026-06-04

---

### Q1: Which areas do you want to discuss for Performance & Battery Emergency?

**Options presented:**
- OCR Polling Strategy — When should we capture screen context? (ScreenContextManager currently runs OCR every 5 seconds continuously. Recommended: Only poll when typing or UI is active)
- MLX Memory Management — When should we unload the model? (LLMEngine currently keeps the ~1.5GB model in memory forever. Recommended: Unload after 5-10 minutes of inactivity)
- Power State Awareness — Should we behave differently on battery? (Recommended: Increase OCR interval or pause pre-fetching when on battery power)

**User Selection:**
- MLX Memory Management — When should we unload the model? (LLMEngine currently keeps the ~1.5GB model in memory forever. Recommended: Unload after 5-10 minutes of inactivity)

**User Input/Notes:**
The user provided a comprehensive list of core architectural requirements that override default assumptions:

1. Main-Thread Decoupling: The CGEventTap callback MUST return the original CGEvent immediately. Move all buffer updates, tracking, and LLMEngine trigger logic completely off the Main Thread to a background queue or Actor.
2. CoreAnimation Ghost UI: Strip SwiftUI out of the inline Ghost Text overlay window. Rewrite the inline ghost text renderer using a raw AppKit NSWindow containing a single CALayer and CATextLayer to drop UI overhead.
3. The Hybrid Inference Engine: Implement a Threshold Gate in CompletionManager using NSSpellChecker for instant, 0-CPU predictions for short words/stop-words. Only spin up MLX model if user pauses typing for >300ms.
4. MLX Memory Management: Implement an inactivity timer in LLMEngine to unload the model after 5 minutes of no keystrokes. Re-load asynchronously when typing resumes.

---

**Outcome:**
Decisions fully captured in `16-CONTEXT.md`. Ready for planning.
