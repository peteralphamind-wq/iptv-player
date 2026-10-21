import AVFoundation
import SwiftUI

@main
struct IPTVPlayerApp: App {
    @StateObject private var store = Store()

    init() {
        // Ton auch bei Stummschalter und im Hintergrund / Bild-in-Bild
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
