import SwiftUI

/// Tabbed settings: General, Notifications, Apify, Profiles, History, About (F8/A3).
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsView(model: model)
                .tabItem { Label("Notifications", systemImage: "bell") }
            ApifySettingsView(model: model)
                .tabItem { Label("Apify", systemImage: "cloud") }
            ProfilesSettingsView(model: model)
                .tabItem { Label("Profiles", systemImage: "person.2") }
            HistorySettingsView(model: model)
                .tabItem { Label("History", systemImage: "chart.xyaxis.line") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 560)
    }
}
