import Foundation
@testable import TypeFlow

func runFIMProbe() async {
    let phrases = [
        "The quick brown ",
        "i want the ghost text to feel natural ",
        "this completion should be useful because ",
        "we need the suggestion to ",
        "public ResponseEntity<User> getUserById(",
        "SELECT * FROM users WHERE "
    ]
    
    // Enable FIM Mode
    UserDefaults.standard.set(true, forKey: "FIMEnabled")
    UserDefaults.standard.set("\(NSHomeDirectory())/Documents/Qwen2.5-Coder-1.5B.Q4_K_M.gguf", forKey: "TestModelPath")
    UserDefaults.standard.set(0.1, forKey: "globalTemperature")
    
    await LLMEngine.shared.prewarmCache()
    guard await LLMEngine.shared.isModelReady else {
        print("Failed to load model")
        return
    }
    
    let profile = await LLMEngine.shared.activeProfile
    print("Model loaded: \(profile.path)")
    print("Family: \(profile.family)")
    print("FIM Enabled: \(profile.promptMode == .fim)")
    
    for phrase in phrases {
        print("--------------------------------------------------")
        print("Testing Phrase: '\(phrase)'")
        
        let prompt = PromptBuilder.shared.buildPrompt(textBeforeCaret: phrase, liveBuffer: "", systemInstructions: "")
        print("Prompt length: \(prompt.count) chars")
        print("Exact FIM Prompt:\n\(prompt)")
        
        let start = Date()
        let result = await LLMEngine.shared.generateCompletion(textBeforeCaret: phrase, liveBuffer: "")
        let elapsed = Date().timeIntervalSince(start) * 1000
        
        print("rawOutput: \(result)") // LLMEngine returns sanitized string now, wait, no, LLMEngine returns raw output from wrapper? No, generateCompletion trims it.
        // Wait, CompletionManager cleans it further. But for the probe, this is fine.
        print("totalGenerationMs: \(String(format: "%.1f", elapsed))ms")
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    await runFIMProbe()
    sem.signal()
}
sem.wait()
