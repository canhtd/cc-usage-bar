import AppKit
import SwiftUI

/// Profile CRUD (F7). Directories are chosen with an open panel -- there is no free-text
/// field anywhere in this app that could tempt a user into pasting a credential.
struct ProfilesSettingsView: View {
    @Bindable var model: AppModel
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(model.preferences.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isActive: profile.id == model.preferences.activeProfileID,
                        model: model
                    )
                    .tag(profile.id)
                }
            }
            .listStyle(.inset)
            Divider()
            toolbar
        }
        .onAppear { selection = selection ?? model.preferences.activeProfileID }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                let profile = Profile(name: "New Profile")
                model.preferences.addProfile(profile)
                model.syncRuntimes()
                selection = profile.id
            } label: {
                Image(systemName: "plus")
            }
            .help("Add a profile")

            Button {
                guard let selection, selection != Profile.defaultID else { return }
                model.preferences.removeProfile(id: selection)
                model.syncRuntimes()
                self.selection = model.preferences.activeProfileID
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selection == nil || model.preferences.profiles.count < 2)
            .help("Remove the selected profile")

            Spacer()
            if let editing {
                Button("Choose Folder…") { chooseFolder(for: editing) }
                if editing.configDirectoryPath != nil {
                    Button("Clear Folder") {
                        var updated = editing
                        updated.configDirectoryPath = nil
                        commit(updated)
                    }
                }
                Button("Make Active") { model.selectProfile(id: editing.id) }
                    .disabled(editing.id == model.preferences.activeProfileID)
            }
        }
        .padding(10)
        .buttonStyle(.bordered)
    }

    private var editing: Profile? {
        model.preferences.profiles.first { $0.id == selection }
    }

    private func commit(_ profile: Profile) {
        model.preferences.updateProfile(profile)
        model.syncRuntimes()
    }

    /// `CLAUDE_CONFIG_DIR` points at a directory; the panel enforces that.
    private func chooseFolder(for profile: Profile) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the CLAUDE_CONFIG_DIR for “\(profile.shortName)”."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = profile
        updated.configDirectoryPath = url.path
        commit(updated)
    }
}

/// One editable row: name plus the directory the profile points at.
private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                TextField("Name", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.body.weight(isActive ? .semibold : .regular))
                if isActive {
                    Text("Active")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(profile.configDirectoryPath ?? "Default Claude Code configuration")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.vertical, 3)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { profile.name },
            set: { newName in
                var updated = profile
                updated.name = newName
                model.preferences.updateProfile(updated)
                // Same path every other edit takes: without it the runtime keeps the old
                // name and the menu bar, tooltip and notifications go on using it.
                model.syncRuntimes()
            })
    }
}
