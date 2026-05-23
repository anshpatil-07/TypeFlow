class PromptBuilder {
    static let shared = PromptBuilder()
    
    private init() {}
    
    func buildPrompt(context: AggregatedContext, tone: String, instructions: String) -> String {
        var prompt = ""
        prompt += "<instruction>\n"
        prompt += "You are a fast, system-wide macOS autocomplete AI.\n"
        prompt += "Your ONLY task is to predict the next 2-5 words the user will type.\n"
        prompt += "CRITICAL RULE: NEVER repeat the input text. ONLY output the immediate continuation.\n"
        prompt += "</instruction>\n\n"
        
        prompt += "<examples>\n"
        prompt += "Input: The quick brown \n"
        prompt += "Continuation: fox jumps over\n\n"
        prompt += "Input: func calculateTotal\n"
        prompt += "Continuation: (items: [Item]) -> Double {\n"
        prompt += "</examples>\n\n"
        
        prompt += "<context>\n"
        prompt += "Tone: \(tone)\n"
        if !instructions.isEmpty {
            prompt += "Custom rules: \(instructions)\n"
        }
        if let clipboard = context.clipboardText, !clipboard.isEmpty {
            prompt += "Clipboard: \(clipboard)\n"
        }
        if let screen = context.screenText, !screen.isEmpty {
            prompt += "Screen: \(screen)\n"
        }
        if let document = context.fullFieldText, !document.isEmpty {
            prompt += "Surrounding text: \(document)\n"
        }
        prompt += "</context>\n\n"
        
        prompt += "Input: \(context.activeLineText)\n"
        prompt += "Continuation: "
        return prompt
    }
}
