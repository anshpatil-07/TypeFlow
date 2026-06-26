import re

with open("CompletionManager.swift", "r") as f:
    content = f.read()

# 1. Remove SuggestionWorkController class entirely
content = re.sub(r'final class SuggestionWorkController: @unchecked Sendable \{.*?(?=\nstruct SuggestionInteractionState)', '', content, flags=re.DOTALL)

# 2. Remove property
content = re.sub(r'\s*private let workController = SuggestionWorkController\(\)', '', content)

with open("CompletionManager.swift", "w") as f:
    f.write(content)
