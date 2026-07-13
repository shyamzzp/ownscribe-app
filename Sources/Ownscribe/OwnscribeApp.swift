import SwiftUI

@main
struct OwnscribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Ensures the SPM executable behaves like a regular, focusable GUI app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct RootView: View {
    enum Tab: Hashable { case record, history, ask, settings }
    @State private var tab: Tab = .record
    @StateObject private var recorder = Recorder()
    @StateObject private var store = MeetingStore()

    var body: some View {
        TabView(selection: $tab) {
            RecordView(store: store)
                .tabItem { Label("Record", systemImage: "record.circle") }
                .tag(Tab.record)

            HistoryView(store: store)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(Tab.history)

            AskView()
                .tabItem { Label("Ask", systemImage: "sparkles") }
                .tag(Tab.ask)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .environmentObject(recorder)
        .padding(.top, 4)
        .onChange(of: recorder.phase) { _, newValue in
            if newValue == .done { store.reload() }
        }
    }
}
