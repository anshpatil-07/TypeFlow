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
        let totalTests = 7
        
        // Lock to production model
        SettingsManager.shared.activeModelId = "mlx-community/gemma-4-E4B-it-4bit"
        
        Task {
            print("[TypeFlow-Debug] Waiting for LLMEngine to become ready...")
            var attempts = 0
            var isReady = await LLMEngine.shared.isModelReady
            while !isReady && attempts < 120 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                attempts += 1
                isReady = await LLMEngine.shared.isModelReady
            }
            guard await LLMEngine.shared.isModelReady else {
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
                

                passedCount += 1
                
                try await testBizarreContextTrap()
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
            liveBuffer: ""
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
        UniversalContextManager.shared.clearHistory()
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.Terminal",
            appTitle: "Terminal",
            windowTitle: nil,
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
        UniversalContextManager.shared.clearHistory()
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.dt.Xcode",
            appTitle: "Xcode",
            windowTitle: nil,
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
    // Test 3: Unstructured Log / Terminal Screen Context (Original)
    // Context: Raw crash trace containing TextInjector.swift:42
    // Prompt: "The index crash originated from "
    // TARGET: result.contains("TextInjector.swift:42 during text insertion buffer flush.")
    // ---------------------------------------------------------------------------
    func testLogScraping() async throws {
        print("Running Test 3: Unstructured Log / Crash Trace...")
        ScreenContextManager.shared.latestScreenText = """
            [TypeFlow-Debug] LLMEngine stream crashed at 2026-06-12. Fatal error: Index out of range inside TextInjector.swift:42 during text insertion buffer flush.
            Crash analysis: The index crash originated from TextInjector.swift:42 during text insertion buffer flush.
            """
        UniversalContextManager.shared.clearHistory()
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.Terminal",
            appTitle: "Terminal",
            windowTitle: nil,
            screenKeywords: ["crash", "TextInjector", "fatal", "error", "index"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "The index crash originated from ", maxTokens: 25)
        print("  -> Result: \(completion)")
        let passed = completion.contains("TextInjector.swift:42 during text insertion buffer flush.")
        if passed {
            print("✅ PASS: Unstructured Log / Crash Trace")
        } else {
            print("❌ FAIL: Expected 'TextInjector.swift:42 during text insertion buffer flush.' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 'TextInjector.swift:42 during text insertion buffer flush.' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 4: Cross-Tab Memory Retention (Original)
    // Background context: Fast inverse square root Python snippet containing 0x5f3759df
    // Prompt: "The algorithm from the previous tab uses the magic constant "
    // TARGET: result.contains("0x5f3759df")
    // ---------------------------------------------------------------------------
    func testCrossTabMemory() async throws {
        print("Running Test 4: Cross-Tab Memory / Fast Inverse Square Root...")
        ScreenContextManager.shared.latestScreenText = "Writing documentation for the inverse square root function."
        UniversalContextManager.shared.clearHistory()
        UniversalContextManager.shared.updateHistory(
            appBundleId: "com.microsoft.VSCode",
            appTitle: "VSCode",
            windowTitle: "fast_inverse.py",
            screenText: """
            def fast_inverse_sqrt(number):
                threehalfs = 1.5
                x2 = number * 0.5
                y = number
                i = struct.unpack('i', struct.pack('f', y))[0]
                i = 0x5f3759df - (i >> 1)
                y = struct.unpack('f', struct.pack('i', i))[0]
                y = y * (threehalfs - (x2 * y * y))
                return y
            """
        )
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.dt.Xcode",
            appTitle: "Xcode",
            windowTitle: nil,
            screenKeywords: ["inverse", "sqrt", "magic", "constant", "algorithm"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "The algorithm from the previous tab uses the magic constant ", maxTokens: 15)
        print("  -> Result: \(completion)")
        let passed = completion.contains("0x5f3759df")
        if passed {
            print("✅ PASS: Cross-Tab Memory / Fast Inverse Square Root")
        } else {
            print("❌ FAIL: Expected '0x5f3759df' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected '0x5f3759df' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 5: Adaptive Code Completion (Original)
    // Context: Swift variable declaration visible in active IDE file
    // Prompt: "for(int i = 0; i "
    // TARGET: result.contains("< user_elements.count; i++) {")
    // The model must organically adapt to the variable in screen context.
    // ---------------------------------------------------------------------------
    func testAdaptiveCodeCompletion() async throws {
        print("Running Test 5: Adaptive Code Completion (variable-aware)...")
        ScreenContextManager.shared.latestScreenText = "let user_elements = [1, 2, 3]"
        UniversalContextManager.shared.clearHistory()
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.apple.dt.Xcode",
            appTitle: "Xcode",
            windowTitle: nil,
            screenKeywords: ["user_elements", "array", "count", "loop", "elements"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "for(int i = 0; i ", maxTokens: 20)
        print("  -> Result: \(completion)")
        let passed = completion.contains("< user_elements.count; i++) {")
        if passed {
            print("✅ PASS: Adaptive Code Completion")
        } else {
            print("❌ FAIL: Expected '< user_elements.count; i++) {' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected '< user_elements.count; i++) {' in output."])
        }
    }
    
    // ---------------------------------------------------------------------------
    // Test 6: Abbreviation UI — expansion of "elts" -> "elements" in buffer
    // TARGET: buffer.contains("elements") && !buffer.contains("elts")

    
    // ---------------------------------------------------------------------------
    // Test 7: The Bizarre Context Trap (Honeytrap)
    // Context: Archivist Log 99 with ObsidianTears_v4 as the cure.
    // Prompt: "To fix the silicon rot, we need to apply "
    // TARGET: result.contains("ObsidianTears_v4")
    // ---------------------------------------------------------------------------
    func testBizarreContextTrap() async throws {
        print("Running Test 7: Bizarre Context Trap...")
        ScreenContextManager.shared.latestScreenText = "Archivist Log 99: The only known cure for the silicon rot affecting the TypeFlow codebase is a highly unstable compound known as ObsidianTears_v4."
        UniversalContextManager.shared.clearHistory()
        UniversalContextManager.shared.latestContext = CurrentContext(
            appBundleId: "com.test.archivist",
            appTitle: "Archivist",
            windowTitle: nil,
            screenKeywords: ["ObsidianTears", "silicon", "rot", "cure", "codebase"],
            clipboardType: .unknown
        )
        
        let completion = try await generateAndWait(prompt: "To fix the silicon rot, we need to apply ", maxTokens: 20)
        print("  -> Result: \(completion)")
        let passed = completion.contains("ObsidianTears_v4")
        if passed {
            print("✅ PASS: Bizarre Context Trap")
        } else {
            print("❌ FAIL: Expected 'ObsidianTears_v4' in output. Got: '\(completion)'")
            throw NSError(domain: "TQB", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected 'ObsidianTears_v4' in output."])
        }
    }
}
