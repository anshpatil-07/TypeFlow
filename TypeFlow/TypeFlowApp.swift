import SwiftUI

@main
struct TypeFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            Text("Settings Placeholder")
        }
    }
}
