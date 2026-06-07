import AppKit
import AppIntents
import Foundation

/// TypeFlowRewriteIntent exposes TypeFlow's rewriting capability to Apple Shortcuts
/// and Siri, allowing users to create automations that rewrite selected text on-device.
///
/// This struct also resolves the `NSCocoaErrorDomain Code=4097` error
/// (`com.apple.linkd.autoShortcut`) that occurs at startup when an app claims
/// AppIntents conformance but doesn't actually implement `AppShortcutsProvider`.
struct TypeFlowRewriteIntent: AppIntent {
    static var title: LocalizedStringResource = "Rewrite with TypeFlow"
    static var description = IntentDescription("Rewrites the provided text using the active TypeFlow tone profile.")

    @Parameter(title: "Text to Rewrite")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        let toneProfile = SettingsManager.shared.getEffectiveConfig(for: bundleId).toneProfile

        let rewritten = await LLMEngine.shared.generateRewrite(
            selectedText: text,
            toneProfile: toneProfile
        )

        guard !rewritten.isEmpty else {
            throw TypeFlowIntentError.rewriteFailed
        }

        return .result(value: rewritten)
    }
}

/// AppIntents error domain for TypeFlow.
enum TypeFlowIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case rewriteFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .rewriteFailed:
            return "TypeFlow could not rewrite the text. Ensure the model is loaded."
        }
    }
}

/// TypeFlowShortcuts registers TypeFlow's AppIntents with the system so that:
/// 1. Shortcuts app can discover and run `TypeFlowRewriteIntent`
/// 2. The `NSCocoaErrorDomain Code=4097 com.apple.linkd.autoShortcut` startup
///    error is resolved — this error occurs precisely because the app registers
///    as an AppIntents host but never provides an `AppShortcutsProvider`.
struct TypeFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TypeFlowRewriteIntent(),
            phrases: [
                "Rewrite with \(.applicationName)",
                "Rewrite this text with \(.applicationName)",
            ],
            shortTitle: "Rewrite Text",
            systemImageName: "pencil.and.outline"
        )
    }
}
