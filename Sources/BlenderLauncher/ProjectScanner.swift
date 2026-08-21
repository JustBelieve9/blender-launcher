import Foundation

/// Ищет .blend в домашней папке через Spotlight и добирает скрытые .autosave/,
/// которые Spotlight не индексирует.
final class ProjectScanner: ObservableObject {
    @Published private(set) var scannedProjects: [RecentFile] = []
    @Published private(set) var projectAutosaves: [RecentFile] = []
    @Published private(set) var isScanning = false
    /// Spotlight ничего не отдал, хотя файлы заведомо есть — вероятно, нет доступа к папкам.
    @Published private(set) var looksBlocked = false

    private let query = NSMetadataQuery()
    private let fm = FileManager.default
    /// Директории из recent-files.txt: в них тоже надо заглянуть за .autosave/.
    private var extraDirectories: Set<URL> = []

    init() {
        query.predicate = NSPredicate(format: "kMDItemFSName LIKE[c] %@", "*.blend")
        query.searchScopes = [NSMetadataQueryUserHomeScope]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gatheringFinished),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
    }

    deinit {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    /// - Parameter knownDirectories: папки известных проектов (из recent-files.txt),
    ///   их тоже проверяем на наличие .autosave/.
    func scan(knownDirectories: Set<URL>) {
        extraDirectories = knownDirectories
        guard !isScanning else { return }

        isScanning = true
        query.stop()
        query.start()
    }

    @objc private func gatheringFinished() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var projects: [String: RecentFile] = [:]
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            let url = URL(fileURLWithPath: path)
            guard Self.isRealProject(url) else { continue }

            let file = RecentFile(
                url: url,
                modified: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date,
                source: .scanned
            )
            projects[file.id] = file
        }

        query.stop()

        let sorted = projects.values.sorted {
            ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast)
        }
        let autosaves = collectProjectAutosaves(near: Set(sorted.map { $0.url.deletingLastPathComponent() }))

        DispatchQueue.main.async {
            self.scannedProjects = Array(sorted.prefix(500))
            self.projectAutosaves = autosaves
            self.looksBlocked = sorted.isEmpty && !self.extraDirectories.isEmpty
            self.isScanning = false
        }
    }

    // MARK: - Скрытые .autosave/ рядом с проектами

    /// Полный обход домашней папки стоит ~20 секунд, поэтому смотрим только в директориях,
    /// где уже известны проекты — это несколько десятков stat вместо рекурсии по диску.
    private func collectProjectAutosaves(near directories: Set<URL>) -> [RecentFile] {
        var result: [RecentFile] = []

        for directory in directories.union(extraDirectories) {
            // Blender называет папку и с точкой, и без — встречаются обе.
            for folderName in [".autosave", "autosave"] {
                let autosaveDir = directory.appendingPathComponent(folderName)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: autosaveDir.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }
                guard let items = try? fm.contentsOfDirectory(
                    at: autosaveDir,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                ) else { continue }

                result += items
                    .filter { $0.pathExtension == "blend" }
                    .map { url in
                        RecentFile(
                            url: url,
                            modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                                .contentModificationDate,
                            source: .autosaveProject
                        )
                    }
            }
        }

        return result.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    // MARK: - Фильтр мусора

    private static let configFileNames: Set<String> = [
        "userpref.blend", "startup.blend", "bookmarks.blend",
    ]

    /// Отсеивает конфиги Blender и пресеты аддонов — это не проекты пользователя.
    static func isRealProject(_ url: URL) -> Bool {
        guard url.pathExtension == "blend" else { return false }
        if configFileNames.contains(url.lastPathComponent.lowercased()) { return false }

        let path = url.path
        if path.contains("/Library/Application Support/Blender/") { return false }
        if path.contains("/Library/Caches/") { return false }
        if path.contains("/.Trash/") { return false }
        // Пресеты и ресурсы аддонов лежат и вне Library — например в папке разработки аддона.
        if path.contains("/addons/") || path.contains("/presets/") || path.contains("/extensions/") {
            return false
        }
        // Автосейвам место в своей панели, а не среди проектов. Папка бывает и скрытой,
        // и обычной — видимую Spotlight индексирует, поэтому она сюда и попадала.
        if path.contains("/.autosave/") || path.contains("/autosave/") { return false }
        return true
    }
}
