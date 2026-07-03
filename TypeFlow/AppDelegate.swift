import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    var accessibilityMonitor: AccessibilityMonitor?
    var overlayWindowController: OverlayWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable stdout and stderr buffering to ensure log lines write to disk immediately during benchmarks
        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        let inputIsolationMode = InputIsolationMode.current
        print("[TypeFlow-InputIsolation] launch \(inputIsolationMode.summary)")


        let isTestingMode = ProcessInfo.processInfo.arguments.contains("-runTQB") || UserDefaults.standard.bool(forKey: "runTQB") || FileManager.default.fileExists(atPath: "/tmp/typeflow_tqb_active")
        if isTestingMode {
            // Redirect stdout and stderr to a log file
            let logPath = "/tmp/typeflow_tqb.log"
            try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
            freopen(logPath, "w", stdout)
            freopen(logPath, "w", stderr)
            setvbuf(stdout, nil, _IONBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)
            print("[TypeFlow-Debug] Redirected output to \(logPath) (unbuffered)")
            
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        
        menuBarManager = MenuBarManager()
        if inputIsolationMode.allowOverlay {
            overlayWindowController = OverlayWindowController()
        } else {
            print("[TypeFlow-InputIsolation] overlay/window startup disabled mode=\(inputIsolationMode.label)")
        }
        
        accessibilityMonitor = AccessibilityMonitor { [weak self] rect in
            self?.overlayWindowController?.moveOverlay(to: rect)
        }
        
        if let monitor = accessibilityMonitor, let overlay = overlayWindowController {
            CompletionManager.shared.setup(accessibilityMonitor: monitor, overlayWindowController: overlay)
        }
        
        // Delay start by 1 second: AXIsProcessTrusted() can return false immediately
        // on launch even when permission IS already granted in System Settings,
        // because the sandbox trust status hasn't propagated yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.accessibilityMonitor?.startWithRetry()
        }
        
        if inputIsolationMode.allowAncillaryStartup {
            AppMonitor.shared.start()
            ClipboardMonitor.shared.start()
        } else {
            print("[TypeFlow-InputIsolation] AppMonitor/ClipboardMonitor startup disabled mode=\(inputIsolationMode.label)")
        }
        NSApp.servicesProvider = TypeFlowServicesProvider()
        NSUpdateDynamicServices()
        

        if isTestingMode {
            print("[TypeFlow-Debug] -runTQB flag detected. Starting TQB Tests...")
            TQBRunner.shared.runTests()
            
            // Open settings window to force foreground active window context
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.menuBarManager?.openSettings()
            }
        }
        
        if ProcessInfo.processInfo.arguments.contains("-runFIMProbe") {
            Task {
                await runInternalFIMProbe()
            }
        }
        
        // Request screen capture permission after a delay when application is finished launching
        // and main window is active.
        if inputIsolationMode.allowAncillaryStartup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                ScreenContextManager.shared.checkAndRequestPermission()
            }
        } else {
            print("[TypeFlow-InputIsolation] screen permission/OCR startup disabled mode=\(inputIsolationMode.label)")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    private func runInternalFIMProbe() async {
        let phrases = [
            "The quick brown ",
            "i want the ghost text to feel natural ",
            "this completion should be useful because ",
            "we need the suggestion to ",
            "public ResponseEntity<User> getUserById(",
            "SELECT * FROM users WHERE "
        ]
        
        UserDefaults.standard.set(true, forKey: "FIMEnabled")
        UserDefaults.standard.set(0.1, forKey: "globalTemperature")
        
        await LLMEngine.shared.prewarmCache()
        
        print("\n\n=== INTERNAL FIM PROBE ===")
        for phrase in phrases {
            let start = Date()
            let rawOutput = await LLMEngine.shared.generateCompletion(textBeforeCaret: phrase, liveBuffer: "")
            let elapsed = Date().timeIntervalSince(start) * 1000
            
            print("Phrase: '\(phrase)'")
            print("  rawOutput: '\(rawOutput)'")
            print("  totalGenerationMs: \(String(format: "%.1f", elapsed))ms")
        }
        print("=== PROBE COMPLETE ===\n\n")
        NSApplication.shared.terminate(nil)
    }
}
