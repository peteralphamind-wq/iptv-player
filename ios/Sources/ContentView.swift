import SwiftUI

private enum Filter {
    static let all = "\u{0}alle"
    static let favorites = "\u{0}favoriten"
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var search = ""
    @State private var group = Filter.all
    @State private var showAdd = false
    @State private var showPlaylists = false
    @State private var showGroups = false

    private var allGroups: [String] {
        var seen = Set<String>()
        return store.channels.compactMap { ch in
            guard !ch.group.isEmpty, seen.insert(ch.group).inserted else { return nil }
            return ch.group
        }
    }

    private var groups: [String] { allGroups.filter { !store.isHidden($0) } }

    private var filtered: [Channel] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return store.channels.filter { ch in
            switch group {
            case Filter.all: if store.isHidden(ch.group) { return false }
            case Filter.favorites: if !store.isFavorite(ch) { return false }
            default: if ch.group != group { return false }
            }
            return query.isEmpty || ch.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.playlists.isEmpty {
                    emptyState
                } else {
                    channelList
                }
            }
            .navigationTitle(store.active?.name ?? "IPTV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showPlaylists = true } label: {
                        Label("Playlists", systemImage: "list.bullet")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showGroups = true } label: {
                            Label("Gruppen auswählen", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .disabled(allGroups.isEmpty)
                        Button {
                            Task { await store.loadActive(refresh: true) }
                        } label: {
                            Label("Playlist neu laden", systemImage: "arrow.clockwise")
                        }
                        .disabled(store.active == nil || store.isLoading)
                    } label: {
                        Label("Mehr", systemImage: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if store.isLoading {
                    ProgressView("Lade Sender …")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .sheet(isPresented: $showAdd) { AddPlaylistView() }
            .sheet(isPresented: $showPlaylists) { PlaylistsView(showAdd: $showAdd) }
            .sheet(isPresented: $showGroups) { GroupPickerView(groups: allGroups, channels: store.channels) }
            .alert("Hinweis", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .onChange(of: store.activeID) { _ in group = Filter.all }
            .onAppear { if !store.favorites.isEmpty { group = Filter.favorites } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Noch keine Playlist gespeichert.")
                .foregroundStyle(.secondary)
            Button("Playlist hinzufügen") { showAdd = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var channelList: some View {
        List {
            ForEach(filtered) { channel in
                Button { Player.play(channel) } label: {
                    ChannelRow(channel: channel, isFavorite: store.isFavorite(channel))
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing) {
                    Button { store.toggleFavorite(channel) } label: {
                        Label("Favorit", systemImage: store.isFavorite(channel) ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
                .contextMenu {
                    Button { store.toggleFavorite(channel) } label: {
                        Label(store.isFavorite(channel) ? "Favorit entfernen" : "Als Favorit",
                              systemImage: store.isFavorite(channel) ? "star.slash" : "star")
                    }
                    Button { Player.openInVLC(channel) } label: {
                        Label("In VLC öffnen", systemImage: "arrow.up.forward.app")
                    }
                    Button { UIPasteboard.general.string = channel.url.absoluteString } label: {
                        Label("Link kopieren", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "Sender suchen")
        .safeAreaInset(edge: .top, spacing: 0) { groupBar }
        .overlay {
            if filtered.isEmpty && !store.isLoading {
                Text(group == Filter.favorites
                     ? "Noch keine Favoriten.\nNach links wischen, um einen Sender zu markieren."
                     : "Keine Sender gefunden.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private var groupBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("★ Favoriten", value: Filter.favorites)
                chip("Alle", value: Filter.all)
                ForEach(groups, id: \.self) { chip($0, value: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(_ title: String, value: String) -> some View {
        Button(title) { group = value }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(group == value ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(group == value ? Color.white : Color.primary)
    }
}

struct ChannelRow: View {
    let channel: Channel
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: channel.logo) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(initials)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).lineLimit(1)
                if !channel.group.isEmpty {
                    Text(channel.group)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
        }
        .contentShape(Rectangle())
    }

    private var initials: String {
        let letters = channel.name.filter { $0.isLetter || $0.isNumber }
        return letters.isEmpty ? "TV" : String(letters.prefix(2)).uppercased()
    }
}
