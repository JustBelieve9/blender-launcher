import Foundation

/// Избранные проекты. Хранятся путями, поэтому переживают перезапуск
/// и не зависят от того, помнит ли сам Blender этот файл.
final class FavoritesStore: ObservableObject {
    @Published private(set) var paths: [String] = []

    private let key = "FavoriteProjects"
    private let fm = FileManager.default

    init() {
        paths = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func contains(_ path: String) -> Bool {
        paths.contains(path)
    }

    func toggle(_ path: String) {
        if let index = paths.firstIndex(of: path) {
            paths.remove(at: index)
        } else {
            paths.append(path)
        }
        persist()
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        persist()
    }

    /// Строит список для показа. Пропавшие файлы не выбрасываем — иначе проект
    /// молча исчезнет из избранного, и будет непонятно, куда он делся.
    func files() -> [RecentFile] {
        let items = paths.map { path -> RecentFile in
            let url = URL(fileURLWithPath: path)
            let exists = fm.fileExists(atPath: path)
            return RecentFile(
                url: url,
                modified: exists ? modificationDate(of: path) : nil,
                source: .favorite,
                isMissing: !exists
            )
        }
        // Доступные сверху и по свежести, пропавшие — в конец списка.
        return items.sorted { lhs, rhs in
            if lhs.isMissing != rhs.isMissing { return !lhs.isMissing }
            return (lhs.modified ?? .distantPast) > (rhs.modified ?? .distantPast)
        }
    }

    private func persist() {
        UserDefaults.standard.set(paths, forKey: key)
    }

    private func modificationDate(of path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
