import SwiftUI

@main
struct BlenderLauncherApp: App {
    @StateObject private var manager = BlenderManager()
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .frame(minWidth: 680, minHeight: 480)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новое окно Blender") { manager.launchNewInstance() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
