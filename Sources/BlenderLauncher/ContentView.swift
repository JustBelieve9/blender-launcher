import SwiftUI

enum ProjectListMode: String, CaseIterable, Identifiable {
    case favorites, recent, scanned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .favorites: return "Избранные"
        case .recent: return "Недавние"
        case .scanned: return "Все"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var manager: BlenderManager
    @State private var filter = ""
    @State private var selection: RecentFile.ID?
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue
    @AppStorage("projectListMode") private var listModeRaw: String = ProjectListMode.recent.rawValue

    private var listMode: ProjectListMode {
        get { ProjectListMode(rawValue: listModeRaw) ?? .recent }
        nonmutating set { listModeRaw = newValue.rawValue }
    }

    private var listModeBinding: Binding<ProjectListMode> {
        Binding(get: { listMode }, set: { listMode = $0 })
    }

    private var currentAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private func cycleAppearance() {
        let modes = AppearanceMode.allCases
        let index = modes.firstIndex(of: currentAppearance) ?? 0
        appearanceModeRaw = modes[(index + 1) % modes.count].rawValue
    }

    private var projects: [RecentFile] {
        let base: [RecentFile]
        switch listMode {
        case .favorites: base = manager.favoriteProjects
        case .recent: base = manager.recentFiles
        case .scanned: base = manager.scannedProjects
        }
        guard !filter.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    /// Выделение живёт поверх обоих списков — ищем в том, что сейчас на экране.
    private var selectedFile: RecentFile? {
        projects.first { $0.id == selection } ?? manager.autosaves.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !manager.isInstalled {
                notInstalledBanner
            }

            HSplitView {
                projectsPane
                autosavesPane
            }

            Divider()
            ActionBar(selected: selectedFile)
        }
        .onAppear { manager.refreshAll() }
        .onExitCommand { selection = nil }
        .navigationTitle("Blender Launcher")
        .toolbar { toolbarContent }
    }

    // MARK: - Панели

    private var projectsPane: some View {
        SectionPane(
            title: "Проекты",
            icon: "cube.fill",
            tint: Theme.accentSecondary,
            files: projects,
            emptyIcon: emptyProjectsIcon,
            emptyText: emptyProjectsText,
            rowIcon: "doc.fill",
            isLoading: listMode == .scanned && manager.isScanning,
            selection: $selection,
            filter: $filter,
            modePicker: listModeBinding
        )
    }

    private var autosavesPane: some View {
        SectionPane(
            title: "Автосейвы",
            icon: "exclamationmark.triangle.fill",
            tint: Theme.warning,
            files: manager.autosaves,
            emptyIcon: "checkmark.circle",
            emptyText: "Автосейвов не найдено",
            rowIcon: "clock.badge.exclamationmark.fill",
            isLoading: false,
            selection: $selection,
            filter: nil,
            modePicker: nil
        )
    }

    private var emptyProjectsIcon: String {
        switch listMode {
        case .favorites: return "star"
        case .recent: return "tray"
        case .scanned: return "magnifyingglass"
        }
    }

    private var emptyProjectsText: String {
        switch listMode {
        case .favorites:
            return "Пока пусто. Нажмите звёздочку у проекта, чтобы он всегда был здесь."
        case .recent:
            return "Список пуст"
        case .scanned:
            if manager.isScanning { return "Ищем .blend файлы…" }
            if manager.scanner.looksBlocked {
                return "Ничего не найдено. Проверьте доступ к папкам в Системных настройках → Конфиденциальность."
            }
            return "Файлы .blend не найдены"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                cycleAppearance()
            } label: {
                Image(systemName: currentAppearance.icon)
            }
            .help("Тема: \(currentAppearance.label) — клик переключает")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                manager.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Обновить списки")
        }
        ToolbarItem(placement: .primaryAction) {
            VersionPicker(style: .toolbar)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                manager.launchNewInstance()
            } label: {
                Label("Новое окно", systemImage: "plus.square.on.square")
            }
            .disabled(!manager.isInstalled)
            .help("Открыть ещё одно независимое окно Blender")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                manager.launchMain()
            } label: {
                Label("Запустить Blender", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(!manager.isInstalled)
        }
    }

    private var notInstalledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text("Blender не найден на диске")
                .font(.system(size: 12))
            Spacer()
            Button("Указать вручную…") { manager.installs.addInstallViaPanel() }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.warning.opacity(0.12))
    }
}

// MARK: - Нижняя панель действий

private struct ActionBar: View {
    @EnvironmentObject var manager: BlenderManager
    let selected: RecentFile?

    private var isSelectedFavorite: Bool {
        guard let selected else { return false }
        return manager.isFavorite(selected)
    }

    private var canFavoriteSelected: Bool {
        guard let selected else { return false }
        switch selected.source {
        case .recent, .scanned, .favorite: return true
        case .autosaveTemp, .autosaveProject: return false
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if let selected {
                Image(systemName: "doc.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selected.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(selected.directory)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            } else {
                Text("Проект не выбран")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                if let selected { manager.toggleFavorite(selected) }
            } label: {
                Image(systemName: isSelectedFavorite ? "star.fill" : "star")
                    .foregroundStyle(isSelectedFavorite ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(selected == nil || !canFavoriteSelected)
            .keyboardShortcut("d", modifiers: .command)
            .help(isSelectedFavorite ? "Убрать из избранного (⌘D)" : "В избранное (⌘D)")

            VersionPicker(style: .compact)

            Button {
                if let selected {
                    manager.launchNewInstance(openingFile: selected.path)
                }
            } label: {
                Label("Открыть", systemImage: "arrow.up.forward.app.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(selected == nil || selected?.isMissing == true || !manager.isInstalled)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

// MARK: - Выбор версии Blender

private struct VersionPicker: View {
    enum Style { case toolbar, compact }

    @EnvironmentObject var manager: BlenderManager
    let style: Style

    var body: some View {
        Menu {
            ForEach(manager.installs.installs) { install in
                Button {
                    manager.installs.activeInstallID = install.id
                } label: {
                    if install.id == manager.installs.activeInstall?.id {
                        Label(install.displayName, systemImage: "checkmark")
                    } else {
                        Text(install.displayName)
                    }
                }
            }
            Divider()
            Button("Добавить версию…") { manager.installs.addInstallViaPanel() }
            Button("Обновить список версий") { manager.installs.refresh() }
        } label: {
            Label(
                manager.installs.activeInstall?.displayName ?? "Blender не найден",
                systemImage: "shippingbox.fill"
            )
            .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!manager.isInstalled)
        .help("Версия Blender для запуска")
    }
}

// MARK: - Панель со списком

private struct SectionPane: View {
    @EnvironmentObject var manager: BlenderManager
    let title: String
    let icon: String
    let tint: Color
    let files: [RecentFile]
    let emptyIcon: String
    let emptyText: String
    let rowIcon: String
    let isLoading: Bool
    @Binding var selection: RecentFile.ID?
    var filter: Binding<String>?
    var modePicker: Binding<ProjectListMode>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            if let modePicker {
                Picker("", selection: modePicker) {
                    ForEach(ProjectListMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            if let filter {
                searchField(filter)
            }
            Divider().opacity(0.5)

            if files.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(files) { file in
                            FileRow(
                                file: file,
                                tint: tint,
                                icon: rowIcon,
                                isSelected: selection == file.id,
                                onSelect: { selection = file.id }
                            )
                        }
                    }
                    .padding(8)
                }
                // Клик по пустому месту снимает выделение.
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }
            }
        }
        .frame(minWidth: 320)
        .background(.background)
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
            Text("\(files.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func searchField(_ filter: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Фильтр", text: filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary.opacity(0.5)))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: emptyIcon)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(emptyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Строка файла

private struct FileRow: View {
    @EnvironmentObject var manager: BlenderManager
    let file: RecentFile
    let tint: Color
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.isMissing ? "questionmark.folder" : icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .white : (file.isMissing ? .secondary : tint))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isSelected ? .white : (file.isMissing ? .secondary : .primary))
                    .lineLimit(1)
                    .strikethrough(file.isMissing, color: .secondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            if let modified = file.modified {
                Text(relative(modified))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
            }

            if canFavorite {
                Button {
                    manager.toggleFavorite(file)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(starColor)
                }
                .buttonStyle(.plain)
                // Пустое место сохраняем всегда, иначе строки дёргаются при наведении.
                .opacity(isFavorite || hovering ? 1 : 0)
                .help(isFavorite ? "Убрать из избранного" : "В избранное")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Двойной клик объявляем первым, иначе одиночный съедает его.
        .onTapGesture(count: 2) {
            onSelect()
            guard !file.isMissing else { return }
            manager.launchNewInstance(openingFile: file.path)
        }
        .onTapGesture(count: 1) { onSelect() }
        .contextMenu {
            Button("Открыть в новом окне Blender") {
                manager.launchNewInstance(openingFile: file.path)
            }
            if manager.installs.installs.count > 1 {
                Menu("Открыть в версии") {
                    ForEach(manager.installs.installs) { install in
                        Button(install.displayName) {
                            manager.launchNewInstance(openingFile: file.path, install: install)
                        }
                    }
                }
            }
            if canFavorite {
                Divider()
                Button(isFavorite ? "Убрать из избранного" : "В избранное") {
                    manager.toggleFavorite(file)
                }
            }
            Divider()
            Button("Показать в Finder") {
                manager.revealInFinder(file)
            }
            .disabled(file.isMissing)
        }
    }

    /// Автосейвы временные — держать их в избранном смысла нет.
    private var canFavorite: Bool {
        switch file.source {
        case .recent, .scanned, .favorite: return true
        case .autosaveTemp, .autosaveProject: return false
        }
    }

    private var isFavorite: Bool { manager.isFavorite(file) }

    private var starColor: Color {
        if isSelected { return .white }
        return isFavorite ? Theme.accent : .secondary
    }

    private var background: Color {
        if isSelected { return Theme.accent }
        return hovering ? Color.primary.opacity(0.06) : .clear
    }

    /// У автосейвов важнее, откуда они, чем полный путь.
    private var subtitle: String {
        if file.isMissing { return "Файл не найден — \(file.directory)" }
        switch file.source {
        case .autosaveTemp: return "Временная папка системы"
        case .autosaveProject:
            let autosaveDir = file.url.deletingLastPathComponent()
            let projectDir = autosaveDir.deletingLastPathComponent()
            return "\(projectDir.lastPathComponent)/\(autosaveDir.lastPathComponent)"
        case .recent, .scanned, .favorite: return file.directory
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
