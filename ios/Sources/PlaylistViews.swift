import SwiftUI
import UniformTypeIdentifiers

struct PlaylistsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var showAdd: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.playlists) { playlist in
                    Button {
                        store.select(playlist)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name).font(.headline)
                                Text("\(playlist.channelCount) Sender · \(playlist.url.isEmpty ? "aus Datei" : "per Link")")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if playlist.id == store.activeID {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    offsets.map { store.playlists[$0] }.forEach { store.delete($0) }
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showAdd = true }
                    } label: {
                        Label("Neue Playlist", systemImage: "plus")
                    }
                }
            }
        }
    }
}

struct AddPlaylistView: View {
    private enum Source: String, CaseIterable {
        case link = "M3U-Link"
        case xtream = "Xtream Codes"
        case file = "Datei"
    }

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var source = Source.link
    @State private var name = ""
    @State private var url = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var fileURL: URL?
    @State private var showImporter = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quelle", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section {
                    TextField("Name (z. B. Mein IPTV)", text: $name)
                }

                switch source {
                case .link:
                    Section {
                        TextField("http://…/get.php?username=…", text: $url, axis: .vertical)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("M3U-Link")
                    }
                case .xtream:
                    Section {
                        TextField("Server, z. B. http://line.example.com", text: $server)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Benutzername", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Passwort", text: $password)
                    } header: {
                        Text("Xtream-Codes-Zugang")
                    }
                case .file:
                    Section {
                        Button(fileURL?.lastPathComponent ?? "Datei auswählen …") { showImporter = true }
                    } header: {
                        Text("M3U-Datei")
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Playlist hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
                if case .success(let picked) = result { fileURL = picked }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var canSave: Bool {
        switch source {
        case .link: return !url.trimmingCharacters(in: .whitespaces).isEmpty
        case .xtream: return !server.isEmpty && !username.isEmpty && !password.isEmpty
        case .file: return fileURL != nil
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let title = name.trimmingCharacters(in: .whitespaces)
            switch source {
            case .link:
                try await store.add(name: title, url: url)
            case .xtream:
                try await store.add(name: title, url: Store.xtreamURL(server: server, username: username, password: password))
            case .file:
                if let fileURL { try await store.importFile(name: title, fileURL: fileURL) }
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
