import AppKit
import Foundation

struct RecentFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let modified: Date?

    var name: String { url.lastPathComponent }
    var path: String { url.path }
    var directory: String { url.deletingLastPathComponent().path }
}

final class BlenderManager: ObservableObject {
    @Published var recentFiles: [RecentFile] = []
    @Published var recentAutosaves: [RecentFile] = []
    @Published var blenderAppPath: String {
        didSet { UserDefaults.standard.set(blenderAppPath, forKey: "BlenderAppPath") }
    }

    private let fm = FileManager.default

    init() {
        blenderAppPath = UserDefaults.standard.string(forKey: "BlenderAppPath") ?? "/Applications/Blender.app"
        refreshAll()
    }

    var appURL: URL { URL(fileURLWithPath: blenderAppPath) }
    var binaryURL: URL { appURL.appendingPathComponent("Contents/MacOS/Blender") }
    var isInstalled: Bool { fm.fileExists(atPath: binaryURL.path) }

    func refreshAll() {
        recentFiles = loadRecentFiles()
        recentAutosaves = loadRecentAutosaves()
    }

    /// Обычный запуск — если Blender уже открыт, macOS активирует существующее окно.
    func launchMain() {
        guard isInstalled else { return }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    /// Запуск отдельного процесса напрямую по бинарю — всегда новый инстанс, новое окно.
    @discardableResult
    func launchNewInstance(openingFile path: String? = nil) -> Bool {
        guard isInstalled else { return false }
        let process = Process()
        process.executableURL = binaryURL
        if let path {
            process.arguments = [path]
        }
        do {
            try process.run()
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    func revealInFinder(_ file: RecentFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func chooseBlenderApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            blenderAppPath = url.path
            refreshAll()
        }
    }

    // MARK: - Recent files (из config Blender)

    private func latestVersionConfigDir() -> URL? {
        let base = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Blender")
        guard let dirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
            return nil
        }
        let versioned: [(Double, URL)] = dirs.compactMap { url in
            guard let v = Double(url.lastPathComponent) else { return nil }
            return (v, url)
        }
        guard let latest = versioned.sorted(by: { $0.0 > $1.0 }).first else { return nil }
        return latest.1.appendingPathComponent("config")
    }

    private func loadRecentFiles() -> [RecentFile] {
        guard let configDir = latestVersionConfigDir() else { return [] }
        let listFile = configDir.appendingPathComponent("recent-files.txt")
        guard let contents = try? String(contentsOf: listFile, encoding: .utf8) else { return [] }

        return contents
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty && fm.fileExists(atPath: $0) }
            .prefix(40)
            .map { path in
                RecentFile(url: URL(fileURLWithPath: path), modified: modificationDate(of: path))
            }
    }

    // MARK: - Autosaves (Blender сохраняет их во временную папку системы)

    private func loadRecentAutosaves() -> [RecentFile] {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else {
            return []
        }
        let autosaves = items.filter {
            $0.pathExtension == "blend" && $0.lastPathComponent.contains("_autosave")
        }
        return autosaves
            .map { RecentFile(url: $0, modified: modificationDate(of: $0.path)) }
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
            .prefix(40)
            .map { $0 }
    }

    private func modificationDate(of path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
