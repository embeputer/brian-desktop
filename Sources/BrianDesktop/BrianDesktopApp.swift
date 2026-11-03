#if os(macOS)
import AppKit
import BrianClient
import SwiftUI

@main
struct BrianDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 760, height: 640)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#else
import Foundation

@main
enum BrianDesktopMain {
    static func main() {
        let message = "Brian Desktop is a macOS app. Run swift test on this OS to check the RPC client.\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
#endif
