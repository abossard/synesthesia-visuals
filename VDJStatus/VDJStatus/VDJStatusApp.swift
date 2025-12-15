import SwiftUI

@main
struct VDJStatusApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Toggle Calibrate") { app.calibrating.toggle() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
