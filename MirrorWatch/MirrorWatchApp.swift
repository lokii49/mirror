import SwiftUI

/// MirrorNotes on Apple Watch (3.1.8, item 9): log a mood or a quick note. The watch never holds
/// the journal key or the journal; each item goes to the iPhone (WatchConnectivity, queued until
/// it's reachable), which saves it encrypted like anything written there.
@main
struct MirrorWatchApp: App {
    @State private var sender = WatchSender.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(sender)
                .onAppear {
                    sender.resumeOnOpen()
                    #if DEBUG
                    // Simulator check: one mood and one synthetic note to the paired iPhone.
                    if CommandLine.arguments.contains("--watchSelfTest") {
                        sender.send(.mood, value: "Grateful")
                        sender.send(.note, value: "Synthetic note from the watch self-test.")
                    }
                    #endif
                }
                // Raising the wrist brings the app back without a new launch: try what's waiting
                // again then too, not only on a cold start.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { sender.resumeOnOpen() }
                }
        }
    }
}
