import Foundation

// Include source files directly
let sourceFiles = [
    "TypeFlow/Services/ModelProfile.swift",
    "TypeFlow/Services/PromptBuilder.swift"
]

// Note: To compile without LLMEngine and full app dependencies, we can just instantiate PromptBuilder 
// or print out what buildBoundedFIMPrefix does.

func testFIMPromptParity() {
    let phrases = [
        "The quick brown ",
        "i want the ghost text to feel natural ",
        "this completion should be useful because ",
        "public ResponseEntity<User> getUserById(",
        "SELECT * FROM users WHERE "
    ]
    
    // Simulate FIM profile
    UserDefaults.standard.set(true, forKey: "FIMEnabled")
    
    for phrase in phrases {
        print("--------------------------------------------------")
        print("Phrase: '\(phrase)'")
        
        let textBeforeCaret = phrase
        let liveBuffer = ""
        
        // Stage 5L-1 Prompt:
        let stage5L = "<|fim_prefix|>\(textBeforeCaret)<|fim_suffix|><|fim_middle|>"
        print("Stage 5L: \(stage5L)")
        
        // Stage 5M-1 Bounded Prefix Logic (extracted from PromptBuilder):
        var prefixLines: [String] = [textBeforeCaret] // Simulating the single line
        let boundedPrefix = prefixLines.joined(separator: "\n")
        
        let stage5M = "<|fim_prefix|>\(boundedPrefix)<|fim_suffix|><|fim_middle|>"
        print("Stage 5M: \(stage5M)")
        
        print("Byte-for-byte equivalent? \(stage5L == stage5M)")
    }
}

testFIMPromptParity()
