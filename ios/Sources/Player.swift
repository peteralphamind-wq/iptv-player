import AVKit
import UIKit

/// Spielt einen Sender im System-Player ab (Vollbild, Bild-in-Bild, AirPlay).
@MainActor
enum Player {
    static func play(_ channel: Channel) {
        let item = AVPlayerItem(url: channel.playableURL)
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = channel.name as NSString
        title.extendedLanguageTag = "und"
        item.externalMetadata = [title]

        let controller = AVPlayerViewController()
        controller.player = AVPlayer(playerItem: item)
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.modalPresentationStyle = .fullScreen

        topViewController()?.present(controller, animated: true) {
            controller.player?.play()
        }
    }

    /// Öffnet den Sender in der App „VLC for Mobile“ (falls installiert)
    static func openInVLC(_ channel: Channel) {
        let encoded = channel.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        if let url = URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
