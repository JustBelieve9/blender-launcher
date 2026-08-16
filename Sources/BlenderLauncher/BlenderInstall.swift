import AppKit
import Foundation

/// Одна установка Blender на диске.
struct BlenderInstall: Identifiable, Hashable {
    let appURL: URL
    let version: String

    var id: String { appURL.path }
    var binaryURL: URL { appURL.appendingPathComponent("Contents/MacOS/Blender") }
    var isValid: Bool { FileManager.default.isExecutableFile(atPath: binaryURL.path) }

    /// «5.2» из «5.2.0» — в UI длинный патч-номер не нужен.
    var shortVersion: String {
        let parts = version.split(separator: ".")
        guard parts.count >= 2 else { return version }
        return "\(parts[0]).\(parts[1])"
    }

    var displayName: String {
        version == Self.unknownVersion
            ? appURL.deletingPathExtension().lastPathComponent
            : "Blender \(shortVersion)"
    }

    static let unknownVersion = "?"

    /// Читает версию из Info.plist бандла. Возвращает nil, если это не Blender.
    static func at(_ appURL: URL) -> BlenderInstall? {
        let binary = appURL.appendingPathComponent("Contents/MacOS/Blender")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let version = (NSDictionary(contentsOf: plistURL)?["CFBundleShortVersionString"] as? String)
            ?? unknownVersion
        return BlenderInstall(appURL: appURL, version: version)
    }
}

/// Находит и хранит список установок Blender.
final class BlenderInstallStore: ObservableObject {
    @Published private(set) var installs: [BlenderInstall] = []
    @Published var activeInstallID: BlenderInstall.ID? {
        didSet { UserDefaults.standard.set(activeInstallID, forKey: Keys.activeInstall) }
    }

    private enum Keys {
        static let activeInstall = "ActiveBlenderInstall"
        static let customPaths = "CustomBlenderPaths"
        /// Ключ из первой версии приложения — переносим как активную установку.
        static let legacyAppPath = "BlenderAppPath"
    }

    private let fm = FileManager.default

    init() {
        migrateLegacyPathIfNeeded()
        activeInstallID = UserDefaults.standard.string(forKey: Keys.activeInstall)
        refresh()
    }

    var activeInstall: BlenderInstall? {
        installs.first { $0.id == activeInstallID } ?? installs.first
    }

    var hasAnyInstall: Bool { !installs.isEmpty }

    func refresh() {
        var found: [String: BlenderInstall] = [:]
        for url in candidateAppURLs() {
            if let install = BlenderInstall.at(url) {
                found[install.id] = install
            }
        }
        installs = found.values.sorted { lhs, rhs in
            lhs.version.compare(rhs.version, options: .numeric) == .orderedDescending
        }

        // Активная установка могла быть удалена с диска — откатываемся на самую новую.
        if activeInstallID == nil || !installs.contains(where: { $0.id == activeInstallID }) {
            activeInstallID = installs.first?.id
        }
    }

    /// Диалог выбора бандла. Путь запоминается, чтобы версия не потерялась после перезапуска.
    func addInstallViaPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Выберите Blender.app"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let install = BlenderInstall.at(url) else {
            presentNotBlenderAlert(url)
            return
        }

        var custom = UserDefaults.standard.stringArray(forKey: Keys.customPaths) ?? []
        if !custom.contains(url.path) {
            custom.append(url.path)
            UserDefaults.standard.set(custom, forKey: Keys.customPaths)
        }
        refresh()
        activeInstallID = install.id
    }

    func removeCustomInstall(_ install: BlenderInstall) {
        var custom = UserDefaults.standard.stringArray(forKey: Keys.customPaths) ?? []
        custom.removeAll { $0 == install.appURL.path }
        UserDefaults.standard.set(custom, forKey: Keys.customPaths)
        refresh()
    }

    func isCustom(_ install: BlenderInstall) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Keys.customPaths) ?? []).contains(install.appURL.path)
    }

    // MARK: - Поиск бандлов

    private func candidateAppURLs() -> [URL] {
        var urls: [URL] = []

        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Blender"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        for dir in searchDirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            urls += items.filter { url in
                url.pathExtension == "app"
                    && url.lastPathComponent.localizedCaseInsensitiveContains("blender")
                    // Иначе лаунчер найдёт сам себя — имя тоже содержит «Blender».
                    && !url.lastPathComponent.localizedCaseInsensitiveContains("launcher")
            }
        }

        urls += (UserDefaults.standard.stringArray(forKey: Keys.customPaths) ?? [])
            .map { URL(fileURLWithPath: $0) }

        return urls
    }

    private func migrateLegacyPathIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Keys.activeInstall) == nil,
              let legacy = defaults.string(forKey: Keys.legacyAppPath)
        else { return }

        defaults.set(legacy, forKey: Keys.activeInstall)
        if legacy != "/Applications/Blender.app" {
            var custom = defaults.stringArray(forKey: Keys.customPaths) ?? []
            if !custom.contains(legacy) {
                custom.append(legacy)
                defaults.set(custom, forKey: Keys.customPaths)
            }
        }
    }

    private func presentNotBlenderAlert(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Это не похоже на Blender"
        alert.informativeText = "В «\(url.lastPathComponent)» нет исполняемого файла Contents/MacOS/Blender."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
