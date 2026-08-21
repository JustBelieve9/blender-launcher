import AppKit
import Combine
import Foundation

enum FileSource {
    case recent
    case scanned
    case favorite
    /// $TMPDIR/<имя>_<PID>_autosave.blend — схема до Blender 5.x.
    case autosaveTemp
    /// <папка проекта>/.autosave/<имя>_<timestamp>.blend — схема Blender 5.x.
    case autosaveProject
}

struct RecentFile: Identifiable, Hashable {
    let url: URL
    let modified: Date?
    var source: FileSource = .recent
    /// Файл был в избранном, но его больше нет на диске.
    var isMissing: Bool = false

    /// Идентификатор по пути, а не UUID: иначе выделение слетало бы после каждого обновления списка.
    var id: String { url.path }

    var name: String { url.lastPathComponent }
    var path: String { url.path }
    var directory: String { url.deletingLastPathComponent().path }

    static func == (lhs: RecentFile, rhs: RecentFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

final class BlenderManager: ObservableObject {
    @Published var recentFiles: [RecentFile] = []
    @Published var autosaves: [RecentFile] = []

    let installs = BlenderInstallStore()
    let scanner = ProjectScanner()
    let favorites = FavoritesStore()

    private let fm = FileManager.default
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Вложенные ObservableObject не транслируют изменения наверх сами.
        installs.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        scanner.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        favorites.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Скрытые .autosave/ находит сканер — подмешиваем их к автосейвам из $TMPDIR.
        scanner.$projectAutosaves
            .receive(on: DispatchQueue.main)
            .sink { [weak self] found in self?.mergeAutosaves(projectAutosaves: found) }
            .store(in: &cancellables)

        refreshAll()
    }

    var isInstalled: Bool { installs.hasAnyInstall }
    var scannedProjects: [RecentFile] { scanner.scannedProjects }
    var isScanning: Bool { scanner.isScanning }
    var favoriteProjects: [RecentFile] { favorites.files() }

    func isFavorite(_ file: RecentFile) -> Bool { favorites.contains(file.path) }

    func toggleFavorite(_ file: RecentFile) { favorites.toggle(file.path) }

    func refreshAll() {
        recentFiles = loadRecentFiles()
        mergeAutosaves(projectAutosaves: scanner.projectAutosaves)
        installs.refresh()

        // Директории недавних проектов — подсказка сканеру, где искать .autosave/.
        let knownDirectories = Set(recentFiles.map { $0.url.deletingLastPathComponent() })
        scanner.scan(knownDirectories: knownDirectories)
    }

    // MARK: - Запуск

    /// Обычный запуск — если Blender уже открыт, macOS активирует существующее окно.
    func launchMain(install: BlenderInstall? = nil) {
        guard let target = install ?? installs.activeInstall else { return }
        NSWorkspace.shared.openApplication(at: target.appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    /// Запуск отдельного процесса напрямую по бинарю — всегда новый инстанс, новое окно.
    @discardableResult
    func launchNewInstance(openingFile path: String? = nil, install: BlenderInstall? = nil) -> Bool {
        guard let target = install ?? installs.activeInstall, target.isValid else {
            NSSound.beep()
            return false
        }

        let process = Process()
        process.executableURL = target.binaryURL
        if let path {
            process.arguments = [path]
        }
        do {
            try process.run()
            return true
        } catch {
            presentLaunchFailure(error, install: target)
            return false
        }
    }

    func revealInFinder(_ file: RecentFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
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
                RecentFile(
                    url: URL(fileURLWithPath: path),
                    modified: modificationDate(of: path),
                    source: .recent
                )
            }
    }

    // MARK: - Автосейвы

    /// Blender держит автосейвы в двух местах, поэтому сливаем оба источника в один список.
    private func mergeAutosaves(projectAutosaves: [RecentFile]) {
        var merged: [String: RecentFile] = [:]
        for file in loadTempAutosaves() + projectAutosaves {
            merged[file.id] = file
        }
        autosaves = merged.values
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    private func loadTempAutosaves() -> [RecentFile] {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else {
            return []
        }
        return items
            .filter { $0.pathExtension == "blend" && $0.lastPathComponent.contains("_autosave") }
            .map { RecentFile(url: $0, modified: modificationDate(of: $0.path), source: .autosaveTemp) }
    }

    private func modificationDate(of path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func presentLaunchFailure(_ error: Error, install: BlenderInstall) {
        let alert = NSAlert()
        alert.messageText = "Не удалось запустить \(install.displayName)"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
