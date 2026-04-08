import SwiftUI

// MARK: - DictationAIApp
//
// Menu-bar-only macOS app. No Dock icon (LSUIElement = YES in Info.plist).
// AppDelegate handles all real work — this SwiftUI App struct is minimal.

@main
struct DictationAIApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Required by SwiftUI App protocol, but the app has no main window.
        Settings { EmptyView() }
    }
}
