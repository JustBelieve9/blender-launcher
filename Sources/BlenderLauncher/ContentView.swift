import SwiftUI

struct ContentView: View {
    @EnvironmentObject var manager: BlenderManager
    @State private var filter = ""
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    private var currentAppearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    private func cycleAppearance() {
        let modes = AppearanceMode.allCases
        let index = modes.firstIndex(of: currentAppearance) ?? 0
        appearanceModeRaw = modes[(index + 1) % modes.count].rawValue
    }

    private var filteredFiles: [RecentFile] {
        filter.isEmpty
            ? manager.recentFiles
            : manager.recentFiles.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !manager.isInstalled {
                notInstalledBanner
            }
            HSplitView {
                SectionPane(
                    title: "Последние проекты",
                    icon: "clock.arrow.circlepath",
                    tint: Theme.accentSecondary,
                    files: filteredFiles,
                    emptyIcon: "tray",
                    emptyText: "Список пуст",
                    filter: $filter,
                    rowIcon: "doc.fill"
                )
                SectionPane(
                    title: "Автосейвы",
                    icon: "exclamationmark.triangle.fill",
                    tint: Theme.warning,
                    files: manager.recentAutosaves,
                    emptyIcon: "checkmark.circle",
                    emptyText: "Автосейвов не найдено",
                    filter: nil,
                    rowIcon: "doc.badge.gearshape.fill"
                )
            }
        }
        .onAppear { manager.refreshAll() }
        .navigationTitle("Blender Launcher")
        .toolbar {
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
    }

    private var notInstalledBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            Text("Blender.app не найден: \(manager.blenderAppPath)")
                .font(.system(size: 12))
            Spacer()
            Button("Выбрать…") { manager.chooseBlenderApp() }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.warning.opacity(0.12))
    }
}

private struct SectionPane: View {
    @EnvironmentObject var manager: BlenderManager
    let title: String
    let icon: String
    let tint: Color
    let files: [RecentFile]
    let emptyIcon: String
    let emptyText: String
    var filter: Binding<String>?
    var rowIcon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
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
                            FileRow(file: file, tint: tint, icon: rowIcon)
                        }
                    }
                    .padding(8)
                }
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
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileRow: View {
    @EnvironmentObject var manager: BlenderManager
    let file: RecentFile
    let tint: Color
    let icon: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(file.directory)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            if let modified = file.modified {
                Text(relative(modified))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                manager.launchNewInstance(openingFile: file.path)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .help("Открыть в новом окне Blender")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            manager.launchNewInstance(openingFile: file.path)
        }
        .contextMenu {
            Button("Открыть в новом окне Blender") {
                manager.launchNewInstance(openingFile: file.path)
            }
            Button("Показать в Finder") {
                manager.revealInFinder(file)
            }
        }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
