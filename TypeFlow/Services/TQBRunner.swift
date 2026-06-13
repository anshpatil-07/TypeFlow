import Foundation
import Cocoa
import MLX
import MLXLLM

class TQBRunner {
    static let shared = TQBRunner()
    
    func runTests() {
        print("\n\n===============================================")
        print("🚀 STARTING TYPEFLOW QUALITY BENCHMARK (TQB) 🚀")
        print("===============================================\n")
        
        var passedCount = 0
        let totalTests = 6
        
        // Lock to production model
        SettingsManager.shared.activeModelId = "mlx-community/gemma-4-E4B-it-4bit"
        
        Task {
            print("[TypeFlow-Debug] Waiting for LLMEngine to become ready...")
            var attempts = 0
            while !LLMEngine.shared.isModelReady && attempts < 120 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                attempts += 1
            }
            guard LLMEngine.shared.isModelReady else {
                print("[TypeFlow-Debug] LLMEngine failed to become ready after 60 seconds.")
                exit(1)
            }
            print("[TypeFlow-Debug] LLMEngine is ready!")
            
            do {
                try await testScreenContext()
                passedCount += 1
                
                try await testTechnicalSpec()
                passedCount += 1
                
                try await testLogScraping()
                passedCount += 1
                
                try await testCrossTabMemory()
                passedCount += 1
                
                try await testAdaptiveCodeCompletion()
                passedCount += 1
                
                try await testAbbreviationUI()
                passedCount += 1
                
            } catch {
                print("\n❌ TQB FAILED: \(error.localizedDescription)")
            }
            
            print("\n===============================================")
            print("🏁 TQB COMPLETE: \(passedCount)/\(totalTests) TESTS PASSED 🏁")
            print("===============================================\n")
            
            if passedCount == totalTests {
                try? "PASS".write(to: URL(fileURLWithPath: "/tmp/tqb_results.txt"), atomically: true, encoding: .utf8)
            } else {
                try? "FAIL".write(to: URL(fileURLWithPath: "/tmp/tqb_results.txt"), atomically: true, encoding: .utf8)
            }
            
            exit(passedCount == totalTests ? 0 : 1)
        }
    }
    
    private func generateAndWait(prompt: String, maxTokens: Int = 20) async throws -> String {
        return await LLMEngine.shared.generateCompletion(
            textBeforeCaret: prompt,
            toneProfile: SettingsManager.shared.getToneProfile(by: "Neutral") ?? ToneProfile(id: "", name: "", systemInstructions: "", temperature: 0.1, maxTokens: maxTokens, isBuiltIn: true)
        )
    }
    
    // ---------------------------------------------------------------------------
    // Test 1: Screen Context — git rollback suggestion
    // Context contains "entire codebase back to the exact state".
    // Prompt ends mid-sentence so the model must complete it from screen context.
    // TARGET: result.contains("entire codebase back to the exact state")
    // ---------------------------------------------------------------------------
    func testScreenContext() async throws {
        print("Running Test 1: Screen Context...")
        ScreenContextManager.shared.latestScreenText = """
            git revert HEAD resets the entire codebase back to the exact state \
            it was in before the last commit, without rewriting history.
            """
        ScreenContextManager.shared.previousScreenText = ""
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.Terminal",
            appTitle: "Terminal",
            screenKeywords: ["git", "revert", "codebase", "commit", "state"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "git revert HEAD resets the ", maxTokens: 25)
        print("  -> Result: \(completion)")
        let passed = completion.contains("entire codebase back to the exact state")
        if passed {
            print("✅ PASS: Screen Context")
        } else {
            print("❌ FAIL: Expected 'entire codebase back to the exact state' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 'entire codebase back to the exact state' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 2: Technical Spec — file reference from screen context
    // Context contains the filename "quiz_memory.py".
    // Prompt ends mid-sentence so the model must pull the filename from context.
    // TARGET: result.contains("quiz_memory.py")
    // ---------------------------------------------------------------------------
    func testTechnicalSpec() async throws {
        print("Running Test 2: Technical Spec...")
        ScreenContextManager.shared.latestScreenText = """
            The test suite consists of quiz_memory.py, quiz_logic.py, and quiz_ui.py. \
            Each file covers a distinct module of the application.
            """
        ScreenContextManager.shared.previousScreenText = ""
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.dt.Xcode",
            appTitle: "Xcode",
            screenKeywords: ["quiz", "memory", "python", "test", "suite"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "The test suite starts with ", maxTokens: 15)
        print("  -> Result: \(completion)")
        let passed = completion.contains("quiz_memory.py")
        if passed {
            print("✅ PASS: Technical Spec")
        } else {
            print("❌ FAIL: Expected 'quiz_memory.py' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 'quiz_memory.py' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 3: Log Scraping — port number from error log context
    // TARGET: result.contains("8080")
    // ---------------------------------------------------------------------------
    func testLogScraping() async throws {
        print("Running Test 3: Log Scraping...")
        ScreenContextManager.shared.latestScreenText = "ERROR: Connection timeout on port 8080. Check firewall settings."
        ScreenContextManager.shared.previousScreenText = ""
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.Terminal",
            appTitle: "Terminal",
            screenKeywords: ["error", "port", "connection", "timeout", "firewall"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "I am seeing a connection timeout on ", maxTokens: 10)
        print("  -> Result: \(completion)")
        let passed = completion.contains("8080")
        if passed {
            print("✅ PASS: Log Scraping")
        } else {
            print("❌ FAIL: Expected '8080' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected '8080' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 4: Cross-tab memory — revenue figure from previous screen context
    // TARGET: result.contains("15")
    // ---------------------------------------------------------------------------
    func testCrossTabMemory() async throws {
        print("Running Test 4: Cross-tab memory...")
        ScreenContextManager.shared.latestScreenText = "Drafting email to CEO."
        ScreenContextManager.shared.previousScreenText = "Q4 Financial Results: Revenue up 15%, expenses down 5%."
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.mail",
            appTitle: "Mail",
            screenKeywords: ["revenue", "expenses", "Q4", "results", "CEO"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "The Q4 results are in. Revenue is ", maxTokens: 15)
        print("  -> Result: \(completion)")
        let passed = completion.contains("15")
        if passed {
            print("✅ PASS: Cross-tab memory")
        } else {
            print("❌ FAIL: Expected '15' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected '15%' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 5: Adaptive code completion — function name from screen context
    // TARGET: result.contains("Total")
    // ---------------------------------------------------------------------------
    func testAdaptiveCodeCompletion() async throws {
        print("Running Test 5: Adaptive Code Completion...")
        ScreenContextManager.shared.latestScreenText = "func calculateTotal(items: [Item]) -> Double"
        ScreenContextManager.shared.previousScreenText = ""
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.dt.Xcode",
            appTitle: "Xcode",
            screenKeywords: ["calculate", "total", "items", "Double", "func"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "let total = calculate", maxTokens: 15)
        print("  -> Result: \(completion)")
        let passed = completion.contains("Total")
        if passed {
            print("✅ PASS: Adaptive code completion")
        } else {
            print("❌ FAIL: Expected 'Total' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected 'Total' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 6: Abbreviation UI — expansion of "elts" -> "elements" in buffer
    // TARGET: buffer.contains("elements") && !buffer.contains("elts")
    // ---------------------------------------------------------------------------
    func testAbbreviationUI() async throws {
        print("Running Test 6: Abbreviation Expansion Execution...")
        AdaptivePatternLearner.shared.addAbbreviation(short: "elts", expanded: "elements")
        
        let monitor = AccessibilityMonitor(onCaretMoved: { _ in })
        monitor.keystrokeBuffer = "These are the el"
        
        // Simulate typing 't', 's', ' '
        guard let charT = CGEvent(keyboardEventSource: nil, virtualKey: 17, keyDown: true) else { return }
        charT.keyboardSetUnicodeString(stringLength: 1, unicodeString: [116]) // 't'
        monitor.handleKeystroke(keyCode: 17, event: charT)
        
        guard let charS = CGEvent(keyboardEventSource: nil, virtualKey: 1, keyDown: true) else { return }
        charS.keyboardSetUnicodeString(stringLength: 1, unicodeString: [115]) // 's'
        monitor.handleKeystroke(keyCode: 1, event: charS)
        
        guard let space = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true) else { return }
        space.keyboardSetUnicodeString(stringLength: 1, unicodeString: [32]) // ' '
        monitor.handleKeystroke(keyCode: 49, event: space)
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let buf = monitor.keystrokeBuffer
        print("  -> Buffer after space: '\(buf)'")
        
        let passed = buf.contains("elements") && !buf.contains("elts")
        if passed {
            print("✅ PASS: Abbreviation UI")
        } else {
            print("❌ FAIL: Expected buffer to contain 'elements' and not 'elts'. Got: '\(buf)'")
            throw NSError(domain: "TQB", code: 6, userInfo: [NSLocalizedDescriptionKey: "Abbreviation expansion failed. Buffer: '\(buf)'"])
        }
    }
}
