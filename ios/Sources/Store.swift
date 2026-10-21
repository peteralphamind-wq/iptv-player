import Foundation

/// Hält Playlists, Sender und Favoriten. Die Liste der Playlists und die Favoriten
/// liegen in UserDefaults, der M3U-Inhalt als Datei in Application Support.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var channels: [Channel] = []
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var hiddenGroups: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard

    init() {
        if let data = defaults.data(forKey: "playlists"),
           let list = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = list
        }
        activeID = defaults.string(forKey: "activeID").flatMap(UUID.init(uuidString:)) ?? playlists.first?.id
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        hiddenGroups = Set(defaults.stringArray(forKey: "hiddenGroups") ?? [])
        Task { await loadActive() }
    }

    var active: Playlist? { playlists.first { $0.id == activeID } }

    // MARK: Playlists

    func add(name: String, url: String) async throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = try await Self.download(trimmed)
        let fallback = URL(string: trimmed)?.host ?? "Playlist"
        try await addPlaylist(name: name.isEmpty ? fallback : name, url: trimmed, text: text)
    }

    func importFile(name: String, fileURL: URL) async throws {
        let access = fileURL.startAccessingSecurityScopedResource()
        defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        let fallback = fileURL.deletingPathExtension().lastPathComponent
        try await addPlaylist(name: name.isEmpty ? fallback : name, url: "", text: text)
    }

    private func addPlaylist(name: String, url: String, text: String) async throws {
        let parsed = await Self.parse(text)
        guard !parsed.isEmpty else { throw AppError.empty }
        let playlist = Playlist(id: UUID(), name: name, url: url, channelCount: parsed.count, updatedAt: Date())
        try write(text, for: playlist.id)
        playlists.append(playlist)
        activeID = playlist.id
        channels = parsed
        save()
    }

    func select(_ playlist: Playlist) {
        activeID = playlist.id
        save()
        Task { await loadActive() }
    }

    func delete(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        try? FileManager.default.removeItem(at: fileURL(for: playlist.id))
        if activeID == playlist.id {
            activeID = playlists.first?.id
            Task { await loadActive() }
        }
        save()
    }

    /// Lädt die aktive Playlist: zuerst aus der gespeicherten Datei, bei `refresh` neu vom Anbieter
    func loadActive(refresh: Bool = false) async {
        guard let playlist = active else {
            channels = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        var text = refresh ? nil : try? String(contentsOf: fileURL(for: playlist.id), encoding: .utf8)
        if text == nil {
            if playlist.url.isEmpty {
                if refresh { errorMessage = "Diese Playlist stammt aus einer Datei. Importiere die Datei neu, um sie zu aktualisieren." }
            } else {
                do {
                    let fresh = try await Self.download(playlist.url)
                    try write(fresh, for: playlist.id)
                    text = fresh
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            if text == nil { text = try? String(contentsOf: fileURL(for: playlist.id), encoding: .utf8) }
        }

        let parsed = await Self.parse(text ?? "")
        guard activeID == playlist.id else { return }  // inzwischen andere Playlist gewählt
        channels = parsed
        if let i = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[i].channelCount = parsed.count
            if refresh { playlists[i].updatedAt = Date() }
        }
        save()
    }

    // MARK: Favoriten

    func isFavorite(_ channel: Channel) -> Bool { favorites.contains(channel.favoriteKey) }

    func toggleFavorite(_ channel: Channel) {
        if favorites.contains(channel.favoriteKey) {
            favorites.remove(channel.favoriteKey)
        } else {
            favorites.insert(channel.favoriteKey)
        }
        save()
    }

    // MARK: Gruppen ein- und ausblenden

    func isHidden(_ group: String) -> Bool { hiddenGroups.contains(group) }

    func setGroup(_ group: String, visible: Bool) {
        if visible { hiddenGroups.remove(group) } else { hiddenGroups.insert(group) }
        save()
    }

    func setGroups(_ groups: [String], visible: Bool) {
        if visible { hiddenGroups.subtract(groups) } else { hiddenGroups.formUnion(groups) }
        save()
    }

    // MARK: Speicher und Netz

    private func save() {
        defaults.set(try? JSONEncoder().encode(playlists), forKey: "playlists")
        defaults.set(activeID?.uuidString, forKey: "activeID")
        defaults.set(Array(favorites), forKey: "favorites")
        defaults.set(Array(hiddenGroups), forKey: "hiddenGroups")
    }

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Playlists", isDirectory: true)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".m3u")
    }

    private func write(_ text: String, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: fileURL(for: id), atomically: true, encoding: .utf8)
    }

    private static func parse(_ text: String) async -> [Channel] {
        await Task.detached(priority: .userInitiated) { M3UParser.parse(text) }.value
    }

    static func download(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            throw AppError.invalidURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        // manche Anbieter sperren unbekannte Player-Kennungen
        request.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppError.http(http.statusCode)
        }
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("#EXTINF") else { throw AppError.notM3U }
        return text
    }

    /// Baut aus Xtream-Codes-Zugangsdaten den M3U-Link (HLS, damit das iPhone die Sender abspielen kann)
    static func xtreamURL(server: String, username: String, password: String) -> String {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        var components = URLComponents(string: base + "/get.php")
        components?.queryItems = [
            URLQueryItem(name: "username", value: username.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "password", value: password.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "type", value: "m3u_plus"),
            URLQueryItem(name: "output", value: "m3u8"),
        ]
        return components?.string ?? base
    }
}
