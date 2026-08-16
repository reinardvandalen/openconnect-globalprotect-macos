import SwiftUI

@main
struct OpenConnectVPNApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.phase.menuBarSymbol)
                .accessibilityLabel(model.phase.title)
        }
        .menuBarExtraStyle(.window)
    }
}
