import SwiftUI

@main
struct LumoApp: App {
    // adaptor to keep AppDelegate for BGTask registration and other system hooks
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
