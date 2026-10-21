import SwiftUI

/// Auswahl, welche Gruppen der Playlist in der Senderliste erscheinen
struct GroupPickerView: View {
    let groups: [String]
    let channels: [Channel]

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var counts: [String: Int] {
        channels.reduce(into: [:]) { $0[$1.group, default: 0] += 1 }
    }

    private var shown: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? groups : groups.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Alle zeigen") { store.setGroups(shown, visible: true) }
                        Spacer()
                        Button("Alle ausblenden") { store.setGroups(shown, visible: false) }
                    }
                    .buttonStyle(.borderless)
                } footer: {
                    Text("Ausgeblendete Gruppen erscheinen nicht mehr unter „Alle“. Einzelne Sender markierst du als Favorit, indem du sie in der Liste nach links wischst.")
                }

                Section {
                    ForEach(shown, id: \.self) { group in
                        Toggle(isOn: Binding(
                            get: { !store.isHidden(group) },
                            set: { store.setGroup(group, visible: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group).lineLimit(2)
                                Text("\(counts[group] ?? 0) Sender")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Gruppe suchen, z. B. DE oder CH")
            .navigationTitle("Gruppen auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
