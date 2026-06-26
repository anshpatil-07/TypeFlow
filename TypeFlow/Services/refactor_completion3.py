import re

with open("CompletionManager.swift", "r") as f:
    lines = f.readlines()

# We need to find `// Adaptive debounce:`
start_index = -1
for i, line in enumerate(lines):
    if "// Adaptive debounce:" in line:
        start_index = i
        break

end_index = -1
for i in range(start_index, len(lines)):
    if "enum RewriteMode" in lines[i]:
        end_index = i
        break

if start_index != -1 and end_index != -1:
    snippet_code = """        // Snippets check
        let activeLine = self.accessibilityMonitor?.getTextBeforeCaret() ?? bufferFallback
        let snippets = SettingsManager.shared.getSnippets()
        for (key, value) in snippets {
            if (key.hasPrefix("/") || key.hasPrefix(";")) && hasWordBoundaryBeforeSuffix(activeLine: activeLine, suffix: key) {
                print("[TypeFlow-Debug] Snippet matched: '\\(key)' -> '\\(value)'")
                activeSnippetKey = key
                
                let resolved = resolveSnippetPlaceholders(value)
                let (displayText, _) = processCursorPlaceholder(resolved)
                
                DispatchQueue.main.async {
                    self.currentCompletion = value
                    if let rect = self.accessibilityMonitor?.getCurrentCaretRect() {
                        self.overlayWindowController?.moveOverlay(to: rect)
                    }
                    self.overlayWindowController?.updateText(displayText)
                }
                return
            }
        }
    }
    
"""
    new_lines = lines[:start_index] + [snippet_code] + lines[end_index-1:]
    with open("CompletionManager.swift", "w") as f:
        f.writelines(new_lines)
    print("Replaced from", start_index, "to", end_index-1)
else:
    print("Could not find bounds")
