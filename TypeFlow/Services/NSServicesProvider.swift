import Cocoa
import Foundation

/// Provides system-wide macOS Services so users can access TypeFlow from any
/// app's right-click context menu, Edit menu, or via the Services menu.
///
/// Services registered in Info.plist:
///   - "Rewrite with TypeFlow"  → rewriteText(_:userData:error:)
///   - "Expand with TypeFlow"   → expandText(_:userData:error:)
@objc class TypeFlowServicesProvider: NSObject {

    private func currentToneProfile() -> ToneProfile {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        return SettingsManager.shared.getEffectiveConfig(for: bundleId).toneProfile
    }

    /// Called by macOS when the user selects "Rewrite with TypeFlow" from the Services menu.
    /// Reads selected text from the pasteboard, rewrites it via the LLM, and writes it back.
    @objc func rewriteText(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text to rewrite." as NSString
            return
        }

        let toneProfile = currentToneProfile()

        // NSServices handlers run on a background thread; block until LLM finishes.
        let semaphore = DispatchSemaphore(value: 0)
        var rewrittenText = ""

        Task {
            rewrittenText = await LLMEngine.shared.generateRewrite(
                selectedText: text,
                toneProfile: toneProfile
            )
            semaphore.signal()
        }

        semaphore.wait()

        guard !rewrittenText.isEmpty else {
            error.pointee = "TypeFlow could not rewrite the selected text." as NSString
            return
        }

        pboard.clearContents()
        pboard.setString(rewrittenText, forType: .string)
    }

    /// Called by macOS when the user selects "Expand with TypeFlow" from the Services menu.
    /// Reads selected text, generates a completion/expansion, and writes it back.
    @objc func expandText(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text to expand." as NSString
            return
        }

        let toneProfile = currentToneProfile()
        let semaphore = DispatchSemaphore(value: 0)
        var expandedText = ""

        Task {
            expandedText = await LLMEngine.shared.generateCompletion(
                textBeforeCaret: text,
                liveBuffer: "",
                toneProfile: toneProfile
            )
            semaphore.signal()
        }

        semaphore.wait()

        guard !expandedText.isEmpty else {
            error.pointee = "TypeFlow could not expand the selected text." as NSString
            return
        }

        pboard.clearContents()
        pboard.setString(text + expandedText, forType: .string)
    }
}
