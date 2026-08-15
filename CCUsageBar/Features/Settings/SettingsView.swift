import SwiftUI

/// Tabbed settings: General, Notifications, Profiles, History, About (F8).
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsView(model: model)
                .tabItem { Label("Notifications", systemImage: "bell") }
            ProfilesSettingsView(model: model)
                .tabItem { Label("Profiles", systemImage: "person.2") }
            HistorySettingsView(model: model)
                .tabItem { Label("History", systemImage: "chart.xyaxis.line") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 460)
    }
}
