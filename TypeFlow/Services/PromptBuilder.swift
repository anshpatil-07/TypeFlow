class PromptBuilder {
    static let shared = PromptBuilder()
    
    private init() {}
    
    func buildPrompt(context: AggregatedContext, tone: String, instructions: String) -> String {
        var prompt = "You are a system-wide macOS autocomplete AI.\n"
        prompt += "Adopt a \(tone) tone.\n"
        
        if !instructions.isEmpty {
            prompt += "<custom_instructions>\n\(instructions)\n</custom_instructions>\n"
        }
        
        if let clipboard = context.clipboardText, !clipboard.isEmpty {
            prompt += "<clipboard>\n\(clipboard)\n</clipboard>\n"
        }
        
        if let screen = context.screenText, !screen.isEmpty {
            prompt += "<screen_context>\n\(screen)\n</screen_context>\n"
        }
        
        if let document = context.fullFieldText, !document.isEmpty {
            prompt += "<document>\n\(document)\n</document>\n"
        }
        
        prompt += "\nComplete the following text seamlessly. Output ONLY the completion, no explanations.\n"
        prompt += "Text: \(context.activeLineText)"
        
        return prompt
    }
}
