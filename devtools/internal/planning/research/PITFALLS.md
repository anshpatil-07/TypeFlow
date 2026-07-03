# Pitfalls Research

## Common Mistakes
1. **Ghost Text Rendering**: Rendering ghost text natively in apps you don't own is impossible. **Prevention**: Use a floating, transparent overlay window anchored to the caret frame.
2. **Caret Frame Detection**: Not all apps implement AX APIs correctly (e.g. Electron apps, Chrome). **Prevention**: Fallback heuristics or disable overlay, offering a separate UI popover.
3. **Latency**: LLM Time to First Token (TTFT) > 150ms. **Prevention**: Continuous prompt caching, aggressively small models (1.5B 4-bit quantization), MLX optimizations.
4. **Battery Drain**: Continuous OCR will destroy battery life. **Prevention**: Only take screenshots when user pauses typing for >300ms, not constantly.

## Phase Mapping
- UI Overlay and Caret tracking must be addressed in the first phase to validate feasibility.
- Battery management should be in the context phase.
