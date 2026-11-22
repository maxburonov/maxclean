import SwiftUI
import AppKit

// MARK: - Uninstaller

struct AppInfo: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var size: Int64 = 0
}

enum AppScanner {
    static func findApps(in dir: URL, depth: Int) -> [URL] {
        var out: [URL] = []
        for c in FS.children(dir) {
            if c.pathExtension == "app" { out.append(c) }
            else if depth > 0, FS.isDir(c) { out += findApps(in: c, depth: depth - 1) }
        }
        return out
    }

    static func info(_ url: URL) -> AppInfo {
        let b = Bundle(url: url)
        let name = (b?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (b?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let ver = (b?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        return AppInfo(url: url, name: name, bundleID: b?.bundleIdentifier ?? "", version: ver)
    }

    static func installedApps() -> [AppInfo] {
        let dirs = [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications")]
        var seen = Set<String>()
        var out: [AppInfo] = []
        for d in dirs {
            for u in findApps(in: d, depth: 2) {
                let i = info(u)
                if i.bundleID.hasPrefix("com.apple.") || i.bundleID == Bundle.main.bundleIdentifier { continue }
                if seen.insert(u.path).inserted { out.append(i) }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func allBundleIDs() -> Set<String> {
        var s = Set<String>()
        for d in ["/Applications", "/System/Applications", "~/Applications",
                  "/System/Library/CoreServices", "/Library/Application Support"] {
            for u in findApps(in: FS.expand(d), depth: 3) {
                if let id = Bundle(url: u)?.bundleIdentifier { s.insert(id.lowercased()) }
            }
        }
        // Audio plaginlar (AU/VST/AAX), panellar va boshqa bundle'lar — ularning sozlama/litsenziyalari "yetim" emas
        let exts: Set<String> = ["component", "vst", "vst3", "aaxplugin", "plugin", "bundle", "prefpane",
                                 "saver", "qlgenerator", "mdimporter", "appex"]
        for d in ["/Library/Audio/Plug-Ins", "~/Library/Audio/Plug-Ins", "/Library/Application Support/Avid/Audio/Plug-Ins",
                  "/Library/PreferencePanes", "~/Library/PreferencePanes", "/Library/Internet Plug-Ins",
                  "/Library/QuickLook", "~/Library/QuickLook", "/Library/Spotlight", "~/Library/Screen Savers"] {
            let root = FS.expand(d).path
            guard FileManager.default.fileExists(atPath: root) else { continue }
            FS.walk(root) { path, name, _, isDir in
                guard isDir, exts.contains((name as NSString).pathExtension.lowercased()) else { return true }
                if let id = Bundle(path: path)?.bundleIdentifier { s.insert(id.lowercased()) }
                return false
            }
        }
        return s
    }

    static let userLeftoverDirs = [
        "Library/Application Support", "Library/Caches", "Library/Preferences", "Library/Preferences/ByHost",
        "Library/Containers", "Library/Group Containers", "Library/Saved Application State", "Library/Logs",
        "Library/HTTPStorages", "Library/WebKit", "Library/Cookies", "Library/LaunchAgents",
        "Library/Application Scripts"
    ]
    static let systemLeftoverDirs = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/LaunchAgents",
        "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Logs"
    ]

    static func matches(_ fileName: String, app: AppInfo, otherIDs: Set<String> = []) -> Bool {
        let n = fileName.lowercased()
        let bid = app.bundleID.lowercased()
        if !bid.isEmpty, n.contains(bid) {
            // com.google.chrome ≠ com.google.chrome.canary — boshqa o'rnatilgan ilovaning fayli bo'lsa, tegmaymiz
            return !otherIDs.contains { $0 != bid && $0.hasPrefix(bid) && n.contains($0) }
        }
        let an = app.name.lowercased()
        guard an.count >= 3 else { return false }
        let base = (n as NSString).deletingPathExtension
        return base == an || base == an.replacingOccurrences(of: " ", with: "")
    }

    static func leftovers(for app: AppInfo) -> [FileEntry] {
        var dirs = userLeftoverDirs.map { FS.home.appendingPathComponent($0) }
        dirs += systemLeftoverDirs.map { URL(fileURLWithPath: $0) }
        var out: [FileEntry] = []
        let others = allBundleIDs()
        for d in dirs {
            for c in FS.children(d) where matches(c.lastPathComponent, app: app, otherIDs: others) {
                guard !Safety.isProtected(c) else { continue }
                out.append(FileEntry(url: c, size: FS.allocatedSize(of: c), modified: FS.modified(c), selected: true))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// O'chirilgan ilovalardan qolib ketgan "yetim" fayllar.
    static func orphans() -> [FileEntry] {
        let installed = allBundleIDs()
        func isReverseDNS(_ s: String) -> Bool {
            s.split(separator: ".").count >= 3 && !s.contains(" ")
        }
        func orphan(_ raw: String) -> Bool {
            let id = raw.lowercased()
            if id.hasPrefix("com.apple.") || id.hasPrefix("group.") || id.hasPrefix("apple") { return false }
            if id.hasPrefix("uz.max.") { return false }
            return !installed.contains { id.hasPrefix($0) || $0.hasPrefix(id) }
        }
        var out: [FileEntry] = []
        let specs: [(String, String?)] = [
            ("Library/Containers", nil),
            ("Library/Application Support", nil),
            ("Library/Caches", nil),
            ("Library/Preferences", "plist"),
            ("Library/Saved Application State", "savedState"),
            ("Library/HTTPStorages", nil),
            ("Library/WebKit", nil)
        ]
        for (dir, ext) in specs {
            for c in FS.children(FS.home.appendingPathComponent(dir)) {
                var name = c.lastPathComponent
                if let ext {
                    guard c.pathExtension == ext else { continue }
                    name = c.deletingPathExtension().lastPathComponent
                }
                guard isReverseDNS(name), orphan(name), !Safety.isProtected(c) else { continue }
                let s = FS.allocatedSize(of: c)
                out.append(FileEntry(url: c, size: s, modified: FS.modified(c), selected: false, note: dir))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}

@MainActor
final class UninstallerModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var loading = false
    @Published var selected: AppInfo?
    @Published var leftovers: [FileEntry] = []
    @Published var findingLeftovers = false
    @Published var search = ""
    @Published var sortBySize = false
    @Published var message: String?
    @Published var failed: [URL] = []
    @Published var orphans: [FileEntry] = []
    @Published var orphansLoading = false
    @Published var showOrphans = false

    var visibleApps: [AppInfo] {
        var a = search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        if sortBySize { a.sort { $0.size > $1.size } }
        return a
    }

    func load() {
        guard !loading else { return }
        loading = true
        Task {
            let list = await Task.detached { AppScanner.installedApps() }.value
            self.apps = list
            self.loading = false
            let sized = await Task.detached(priority: .utility) { () -> [String: Int64] in
                var d: [String: Int64] = [:]
                for a in list { d[a.id] = FS.allocatedSize(of: a.url) }
                return d
            }.value
            for i in self.apps.indices { self.apps[i].size = sized[self.apps[i].id] ?? 0 }
        }
    }

    func select(_ app: AppInfo) {
        selected = app
        showOrphans = false
        leftovers = []
        findingLeftovers = true
        message = nil; failed = []
        Task {
            let l = await Task.detached { AppScanner.leftovers(for: app) }.value
            if self.selected?.id == app.id { self.leftovers = l; self.findingLeftovers = false }
        }
    }

    func toggleLeftover(_ id: UUID) {
        if let i = leftovers.firstIndex(where: { $0.id == id }) { leftovers[i].selected.toggle() }
    }

    func uninstall(resetOnly: Bool = false) {
        guard let app = selected else { return }
        for r in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) { r.terminate() }
        var entries = leftovers.filter(\.selected)
        if !resetOnly { entries.insert(FileEntry(url: app.url, size: app.size, modified: nil, selected: true), at: 0) }
        let toRemove = entries
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let r = await Task.detached { Remover.remove(toRemove, permanently: false) }.value
            self.failed = r.failed
            if resetOnly {
                self.message = T("\(app.name) sozlamalari tiklandi (\(Format.bytes(r.freed))).", "\(app.name) was reset (\(Format.bytes(r.freed))).", "\(app.name) сброшено (\(Format.bytes(r.freed))).")
                self.select(app)
            } else {
                self.message = T("\(app.name): \(Format.bytes(r.freed)) Savatga yuborildi.", "\(app.name): \(Format.bytes(r.freed)) moved to Trash.", "\(app.name): \(Format.bytes(r.freed)) перемещено в Корзину.")
                if !r.failed.contains(app.url) {
                    self.apps.removeAll { $0.id == app.id }
                    self.selected = nil
                    self.leftovers = []
                }
            }
        }
    }

    func adminRemoveFailed() {
        let paths = failed.filter { !Safety.isProtected($0) }.map { Shell.quote($0.path) }
        guard !paths.isEmpty else { return }
        let r = Admin.run("/bin/rm -rf " + paths.joined(separator: " "))
        if r.ok {
            message = T("Administrator huquqi bilan o'chirildi.", "Removed with administrator rights.", "Удалено с правами администратора.")
            failed = []
            if let s = selected, !FS.exists(s.url) { apps.removeAll { $0.id == s.id }; selected = nil; leftovers = [] }
        } else {
            message = T("Xato: \(r.out)", "Error: \(r.out)", "Ошибка: \(r.out)")
        }
    }

    func loadOrphans() {
        showOrphans = true
        selected = nil
        guard !orphansLoading else { return }
        orphansLoading = true
        Task {
            let o = await Task.detached { AppScanner.orphans() }.value
            self.orphans = o; self.orphansLoading = false
        }
    }

    func toggleOrphan(_ id: UUID) {
        if let i = orphans.firstIndex(where: { $0.id == id }) { orphans[i].selected.toggle() }
    }

    func removeOrphans() {
        let sel = orphans.filter(\.selected)
        Task {
            let r = await Task.detached { Remover.remove(sel, permanently: false) }.value
            let failed = Set(r.failed)
            self.orphans.removeAll { $0.selected && !failed.contains($0.url) }
            self.message = T("\(Format.bytes(r.freed)) Savatga yuborildi.", "\(Format.bytes(r.freed)) moved to Trash.", "\(Format.bytes(r.freed)) перемещено в Корзину.")
        }
    }
}

struct UninstallerView: View {
    @EnvironmentObject var model: UninstallerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "xmark.app", title: T("Ilovalarni o'chirish", "Uninstaller", "Деинсталлятор"),
                       subtitle: T("Ilova + barcha qoldiqlari (kesh, sozlama, konteyner, agent) bilan birga", "Apps together with all leftovers (caches, prefs, containers, agents)", "Приложения вместе со всеми остатками (кэш, настройки, контейнеры, агенты)"))
            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(T("Qidirish", "Search", "Поиск"), text: $model.search).textFieldStyle(.roundedBorder)
                        Toggle(T("Hajm bo'yicha saralash", "Sort by size", "По размеру"), isOn: $model.sortBySize).toggleStyle(.switch).controlSize(.small)
                        Button { model.loadOrphans() } label: {
                            Label(T("Yetim qoldiqlar", "Orphaned leftovers", "Остатки удалённых приложений"), systemImage: "questionmark.folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(GhostButtonStyle())
                        if model.loading { ProgressView().frame(maxWidth: .infinity) }
                        List(model.visibleApps, id: \.id) { app in
                            HStack {
                                Image(nsImage: IconCache.icon(app.url.path))
                                    .resizable().frame(width: 26, height: 26)
                                VStack(alignment: .leading) {
                                    Text(app.name).lineLimit(1)
                                    Text(app.size > 0 ? Format.bytes(app.size) : "…").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(model.selected?.id == app.id ? Theme.accent.opacity(0.3) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(app) }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(width: 300)

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.showOrphans { orphansPanel } else { appPanel }
                        if let m = model.message { Text(m).foregroundColor(Theme.green) }
                        if !model.failed.isEmpty {
                            HStack {
                                Text(T("\(model.failed.count) ta element ruxsat talab qiladi", "\(model.failed.count) items need permission", "\(model.failed.count) элем. требуют прав")).foregroundColor(Theme.orange)
                                Button(T("Administrator bilan o'chirish", "Remove as administrator", "Удалить как администратор")) { model.adminRemoveFailed() }
                                    .buttonStyle(GhostButtonStyle())
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .onAppear { if model.apps.isEmpty { model.load() } }
    }

    @ViewBuilder var appPanel: some View {
        if let app = model.selected {
            HStack(spacing: 14) {
                Image(nsImage: IconCache.icon(app.url.path)).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading) {
                    Text(app.name).font(.title2.bold())
                    Text("\(app.bundleID)  \(app.version)").font(.caption).foregroundStyle(.secondary)
                    Text(T("Ilova: \(Format.bytes(app.size)) · Qoldiqlar: \(Format.bytes(model.leftovers.reduce(0) { $0 + $1.size }))", "App: \(Format.bytes(app.size)) · Leftovers: \(Format.bytes(model.leftovers.reduce(0) { $0 + $1.size }))", "Приложение: \(Format.bytes(app.size)) · Остатки: \(Format.bytes(model.leftovers.reduce(0) { $0 + $1.size }))"))
                        .font(.caption)
                }
                Spacer()
            }
            Divider().opacity(0.3)
            if model.findingLeftovers {
                ProgressView(T("Qoldiqlar qidirilmoqda…", "Looking for leftovers…", "Поиск остатков…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.leftovers) { f in FileRow(entry: f, toggle: { model.toggleLeftover(f.id) }, showDate: false) }
                    .scrollContentBackground(.hidden)
            }
            HStack {
                Button(T("Sozlamalarni tiklash (Reset)", "Reset app", "Сбросить")) { model.uninstall(resetOnly: true) }
                    .buttonStyle(GhostButtonStyle()).help(T("Ilova qoladi, faqat kesh va sozlamalari o'chadi", "The app stays; only its caches and settings are removed", "Приложение остаётся, удаляются только кэш и настройки"))
                Spacer()
                Button(T("To'liq o'chirish", "Uninstall", "Удалить")) { model.uninstall() }.buttonStyle(GlowButtonStyle())
            }
        } else {
            EmptyState(icon: "app.dashed", text: T("Chapdan ilovani tanlang", "Select an app on the left", "Выберите приложение слева"))
        }
    }

    @ViewBuilder var orphansPanel: some View {
        Text(T("Yetim qoldiqlar", "Orphaned leftovers", "Остатки удалённых приложений")).font(.title2.bold())
        Text(T("O'chirilgan ilovalardan qolgan fayllar. Avtomatik belgilanmaydi — ko'rib chiqib tanlang.", "Files left behind by deleted apps. Nothing is preselected — review and choose.", "Файлы, оставшиеся от удалённых приложений. Ничего не выбрано заранее — проверьте и выберите."))
            .font(.caption).foregroundStyle(.secondary)
        if model.orphansLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.orphans.isEmpty {
            EmptyState(icon: "checkmark.circle", text: T("Yetim qoldiq topilmadi", "No orphaned files found", "Остатков не найдено"))
        } else {
            List(model.orphans) { f in FileRow(entry: f, toggle: { model.toggleOrphan(f.id) }, showDate: false) }
                .scrollContentBackground(.hidden)
            HStack {
                Text(T("Jami: \(Format.bytes(model.orphans.reduce(0) { $0 + $1.size }))", "Total: \(Format.bytes(model.orphans.reduce(0) { $0 + $1.size }))", "Всего: \(Format.bytes(model.orphans.reduce(0) { $0 + $1.size }))"))
                Spacer()
                Button(T("Tanlanganlarni Savatga", "Move selected to Trash", "Выбранное в Корзину")) { model.removeOrphans() }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(!model.orphans.contains(where: \.selected))
            }
        }
    }
}

// MARK: - Avto-ishga tushish (Launch Agents / Daemons)

struct LaunchItem: Identifiable, Sendable {
    enum Scope: String, Sendable {
        case user, globalAgent, daemon
        var title: String {
            switch self {
            case .user: return T("Foydalanuvchi", "User", "Пользователь")
            case .globalAgent: return T("Global agent", "Global agent", "Глобальный агент")
            case .daemon: return T("Tizim daemoni", "System daemon", "Системный демон")
            }
        }
    }
    var id: String { path }
    let path: String
    let label: String
    let program: String
    let scope: Scope
    var disabled: Bool
}

enum LaunchScanner {
    static func disabledLabels(domain: String) -> Set<String> {
        let out = Shell.run("/bin/launchctl", ["print-disabled", domain]).out
        var s = Set<String>()
        for line in out.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("\"") else { continue }
            let rest = l.dropFirst()
            guard let end = rest.firstIndex(of: "\"") else { continue }
            let label = String(rest[rest.startIndex..<end])
            if l.contains("=> disabled") || l.contains("=> true") { s.insert(label) }
        }
        return s
    }

    static func load() -> [LaunchItem] {
        let uid = getuid()
        let userDisabled = disabledLabels(domain: "gui/\(uid)")
        let sysDisabled = disabledLabels(domain: "system")
        let dirs: [(URL, LaunchItem.Scope)] = [
            (FS.home.appendingPathComponent("Library/LaunchAgents"), .user),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon)
        ]
        var out: [LaunchItem] = []
        for (dir, scope) in dirs {
            for f in FS.children(dir) where f.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: f) as? [String: Any] ?? [:]
                let label = dict["Label"] as? String ?? f.deletingPathExtension().lastPathComponent
                if label.hasPrefix("com.apple.") { continue }
                let prog = (dict["Program"] as? String)
                    ?? ((dict["ProgramArguments"] as? [String])?.first) ?? "—"
                let plistDisabled = dict["Disabled"] as? Bool ?? false
                let dis = plistDisabled || (scope == .daemon ? sysDisabled.contains(label) : userDisabled.contains(label))
                out.append(LaunchItem(path: f.path, label: label, program: prog, scope: scope, disabled: dis))
            }
        }
        return out.sorted { $0.label < $1.label }
    }
}

@MainActor
final class StartupModel: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var loading = false
    @Published var message: String?

    func load() {
        loading = true
        Task {
            let l = await Task.detached { LaunchScanner.load() }.value
            self.items = l; self.loading = false
        }
    }

    func setEnabled(_ item: LaunchItem, _ on: Bool) {
        let uid = getuid()
        if item.scope == .daemon {
            let cmd = on
                ? "launchctl enable \(Shell.quote("system/" + item.label)); launchctl bootstrap system \(Shell.quote(item.path)) 2>/dev/null; true"
                : "launchctl disable \(Shell.quote("system/" + item.label)); launchctl bootout \(Shell.quote("system/" + item.label)) 2>/dev/null; true"
            let r = Admin.run(cmd)
            if !r.ok { message = r.out; return }
        } else {
            Shell.run("/bin/launchctl", [on ? "enable" : "disable", "gui/\(uid)/\(item.label)"])
            if on {
                Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", item.path])
            } else {
                Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(item.label)"])
            }
        }
        message = "\(item.label) \(on ? T("yoqildi", "enabled", "включено") : T("o'chirildi", "disabled", "отключено"))."
        load()
    }

    func remove(_ item: LaunchItem) {
        let uid = getuid()
        if item.scope == .user {
            Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(item.label)"])
            let e = FileEntry(url: URL(fileURLWithPath: item.path), size: 0, modified: nil, selected: true)
            _ = Remover.remove([e], permanently: false)
        } else {
            let domain = item.scope == .daemon ? "system" : "gui/\(uid)"
            let r = Admin.run("launchctl bootout \(Shell.quote(domain + "/" + item.label)) 2>/dev/null; /bin/rm -f \(Shell.quote(item.path))")
            if !r.ok { message = r.out; return }
            History.add("AGENT O'CHIRILDI\t\(item.path)")
        }
        message = T("\(item.label) olib tashlandi.", "\(item.label) removed.", "\(item.label) удалено.")
        load()
    }
}

struct StartupView: View {
    @EnvironmentObject var model: StartupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "power", title: T("Avto-ishga tushish", "Launch Agents", "Автозапуск"),
                       subtitle: T("Fon agentlari va daemonlar — Mac'ni sekinlashtiradiganlarini o'chiring", "Background agents and daemons — turn off the ones slowing your Mac down", "Фоновые агенты и демоны — отключите те, что тормозят Mac")) {
                HStack {
                    Button("Login Items…") { Permissions.openLoginItems() }.buttonStyle(GhostButtonStyle())
                    Button(T("Yangilash", "Refresh", "Обновить")) { model.load() }.buttonStyle(GhostButtonStyle())
                }
            }
            if let m = model.message { Text(m).foregroundColor(Theme.green) }
            if model.loading && model.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty {
                EmptyState(icon: "checkmark.circle", text: T("Uchinchi tomon agentlari yo'q", "No third-party agents", "Сторонних агентов нет"))
            } else {
                List(model.items) { item in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(get: { !item.disabled }, set: { model.setEnabled(item, $0) }))
                            .toggleStyle(.switch).labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(.body.weight(.medium))
                            Text(item.program).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(item.scope.title).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        Button { FS.reveal(URL(fileURLWithPath: item.path)) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                        Button { model.remove(item) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help(T("Butunlay olib tashlash", "Remove completely", "Удалить полностью"))
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
        .onAppear { if model.items.isEmpty { model.load() } }
    }
}
