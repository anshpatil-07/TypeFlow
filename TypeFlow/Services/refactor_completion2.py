import re

with open("CompletionManager.swift", "r") as f:
    content = f.read()

# Remove workController.cancelAll()
content = content.replace("workController.cancelAll()\n", "")
content = content.replace("workController.cancelAll()", "")

# Rename onTextChanged
content = content.replace("func onTextChanged(bufferFallback: String = \"\") {", "func handleLocalTextChanges(bufferFallback: String = \"\") {")

# Remove isGenerationRunning check
content = re.sub(r'\s*if workController\.isGenerationRunning \{.*?\n\s*\}', '', content, flags=re.DOTALL)

with open("CompletionManager.swift", "w") as f:
    f.write(content)
