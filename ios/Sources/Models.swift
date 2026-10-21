import Foundation

struct Channel: Identifiable, Hashable, Sendable {
    let id: String        // eindeutig pro Zeile der Playlist
    let name: String
    let logo: URL?
    let group: String
    let url: URL

    /// Schlüssel für Favoriten: bleibt gleich, wenn die Playlist neu geladen wird
    var favoriteKey: String { url.absoluteString }

    /// Xtream-Live-Streams (.ts) kann AVPlayer nicht abspielen, die .m3u8-Variante schon
    var playableURL: URL {
        let s = url.absoluteString
        guard s.contains("/live/"), s.hasSuffix(".ts") else { return url }
        return URL(string: String(s.dropLast(3)) + ".m3u8") ?? url
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var url: String       // leer, wenn aus einer Datei importiert
    var channelCount: Int
    var updatedAt: Date
}

enum AppError: LocalizedError {
    case invalidURL
    case http(Int)
    case notM3U
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Der Link ist ungültig."
        case .http(let code): return "Der Anbieter antwortet mit Fehler \(code). Stimmen Benutzername und Passwort?"
        case .notM3U: return "Unter diesem Link liegt keine M3U-Playlist."
        case .empty: return "In dieser Playlist wurden keine Sender gefunden."
        }
    }
}

enum M3UParser {
    private static let attributeRegex = try! NSRegularExpression(pattern: #"([\w-]+)="([^"]*)""#)

    static func parse(_ text: String) -> [Channel] {
        var channels: [Channel] = []
        var name: String?
        var logo: String?
        var group: String?
        var extgrp: String?

        text.enumerateLines { raw, _ in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return }

            if line.hasPrefix("#EXTINF") {
                let (meta, title) = splitTitle(line)
                let attrs = attributes(meta)
                name = title.isEmpty ? attrs["tvg-name"] : title
                logo = attrs["tvg-logo"]
                group = attrs["group-title"]
            } else if line.hasPrefix("#EXTGRP:") {
                extgrp = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") || line.hasPrefix("\u{FEFF}") {
                return
            } else if let url = URL(string: line), url.scheme != nil {
                let g = (group?.isEmpty == false ? group : extgrp) ?? ""
                channels.append(Channel(
                    id: "\(channels.count)|\(line)",
                    name: name ?? url.lastPathComponent,
                    logo: logo.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                    group: g,
                    url: url
                ))
                name = nil; logo = nil; group = nil; extgrp = nil
            }
        }
        return channels
    }

    /// Trennt "#EXTINF:-1 attr=\"a,b\",Titel" am ersten Komma ausserhalb von Anführungszeichen
    private static func splitTitle(_ line: String) -> (String, String) {
        var inQuotes = false
        for idx in line.indices {
            let c = line[idx]
            if c == "\"" {
                inQuotes.toggle()
            } else if c == ",", !inQuotes {
                let title = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                return (String(line[..<idx]), title)
            }
        }
        return (line, "")
    }

    private static func attributes(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        let ns = s as NSString
        for m in attributeRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
        }
        return result
    }
}
