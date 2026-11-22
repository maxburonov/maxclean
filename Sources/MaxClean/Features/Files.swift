import SwiftUI
import AppKit
import CryptoKit

@MainActor
func pickFolder() -> URL? {
    let p = NSOpenPanel()
    p.canChooseDirectories = true
    p.canChooseFiles = false
    p.allowsMultipleSelection = false
    p.prompt = T("Tanlash", "Choose", "Выбрать")
    return p.runModal() == .OK ? p.url : nil
}

func shortPath(_ url: URL) -> String {
    url.path.replacingOccurrences(of: FS.home.path, with: "~")
}

/// Uy papkasini aylanishda o'tkazib yuboriladigan joylar.
enum WalkRules {
    static func skipDir(_ path: String, name: String, root: String) -> Bool {
        if path == root { return false }
        if name.hasPrefix(".") { return true }
        let lib = FS.home.path + "/Library"
        return path == lib || path.hasPrefix("/System") || path == "/Volumes" || path == "/private"
    }
}

// MARK: - Katta va eski fayllar

enum LargeFileScanner {
    static func scan(root: URL, minSize: Int64, olderThanDays days: Int) -> [FileEntry] {
        let cutoff: Date? = days > 0 ? Date().addingTimeInterval(-Double(days) * 86400) : nil
        let rootPath = root.path
        var out: [FileEntry] = []
        FS.walk(rootPath) { path, name, st, isDir in
            if isDir {
                if WalkRules.skipDir(path, name: name, root: rootPath) { return false }
                let ext = (name as NSString).pathExtension
                guard !ext.isEmpty, FS.packageExtensions.contains(ext) else { return true }
                // Paket (.app, .logicx …) — bitta element sifatida
                let size = FS.allocatedSize(of: URL(fileURLWithPath: path))
                let mod = FS.date(st.st_mtimespec)
                if size >= minSize, cutoff.map({ mod < $0 }) ?? true {
                    out.append(FileEntry(url: URL(fileURLWithPath: path), size: size, modified: mod, selected: false))
                }
                return false
            }
            guard !name.hasPrefix(".") else { return true }
            let size = Int64(st.st_blocks) * 512
            guard size >= minSize else { return true }
            let mod = FS.date(st.st_mtimespec)
            if let cutoff, mod > cutoff { return true }
            out.append(FileEntry(url: URL(fileURLWithPath: path), size: size, modified: mod, selected: false))
            return true
        }
        return out.sorted { $0.size > $1.size }
    }
}

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var files: [FileEntry] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var minMB: Int = 100
    @Published var olderThanDays: Int = 0
    @Published var root: URL = FS.home
    @Published var message: String?
    @Published var filter = ""

    var selectedSize: Int64 { files.filter(\.selected).reduce(0) { $0 + $1.size } }
    var total: Int64 { files.reduce(0) { $0 + $1.size } }
    var visible: [FileEntry] {
        filter.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    func scan() {
        guard !scanning else { return }
        scanning = true; message = nil
        let root = root, minBytes = Int64(minMB) * 1_048_576, days = olderThanDays
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                LargeFileScanner.scan(root: root, minSize: minBytes, olderThanDays: days)
            }.value
            self.files = r
            self.scanning = false
            self.scanned = true
        }
    }

    func toggle(_ id: UUID) {
        if let i = files.firstIndex(where: { $0.id == id }) { files[i].selected.toggle() }
    }

    func undo() {
        let n = UndoStore.restore()
        message = T("\(n) ta fayl joyiga qaytarildi", "\(n) files restored", "Восстановлено файлов: \(n)")
        scan()
    }

    func removeSelected() {
        let sel = files.filter(\.selected)
        Task {
            let r = await Task.detached { Remover.remove(sel, permanently: false) }.value
            let failed = Set(r.failed)
            self.files.removeAll { $0.selected && !failed.contains($0.url) }
            self.message = T("\(Format.bytes(r.freed)) Savatga yuborildi.",
                             "\(Format.bytes(r.freed)) moved to Trash.",
                             "\(Format.bytes(r.freed)) перемещено в Корзину.")
        }
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var model: LargeFilesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "doc.badge.ellipsis",
                       title: T("Katta va eski fayllar", "Large & Old Files", "Большие и старые файлы"),
                       subtitle: T("Joyni eng ko'p egallayotgan fayllar — Logic loyihalari va .app paketlari ham",
                                   "Files that take the most space — including Logic projects and .app bundles",
                                   "Файлы, занимающие больше всего места — включая проекты Logic и .app"))
            Card {
                HStack(spacing: 14) {
                    Button {
                        if let u = pickFolder() { model.root = u }
                    } label: {
                        Label(shortPath(model.root), systemImage: "folder")
                    }.buttonStyle(GhostButtonStyle())
                    Picker(T("Kamida", "At least", "Не менее"), selection: $model.minMB) {
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1024)
                        Text("5 GB").tag(5120)
                    }.frame(width: 190)
                    Picker(T("Yoshi", "Age", "Возраст"), selection: $model.olderThanDays) {
                        Text(T("Har qanday", "Any", "Любой")).tag(0)
                        Text(T("1 oydan eski", "Older than 1 month", "Старше месяца")).tag(30)
                        Text(T("6 oydan eski", "Older than 6 months", "Старше 6 месяцев")).tag(180)
                        Text(T("1 yildan eski", "Older than 1 year", "Старше года")).tag(365)
                    }.frame(width: 240)
                    Spacer()
                    Button(model.scanning ? T("Qidirilmoqda…", "Searching…", "Поиск…") : T("Qidirish", "Search", "Найти")) {
                        model.scan()
                    }
                    .buttonStyle(GlowButtonStyle()).disabled(model.scanning)
                }
            }
            if !model.files.isEmpty {
                TextField(T("Nomi bo'yicha filtr", "Filter by name", "Фильтр по имени"), text: $model.filter)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
            }
            if model.scanning {
                ProgressView(T("Fayllar ko'rib chiqilmoqda…", "Scanning files…", "Просмотр файлов…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.files.isEmpty {
                EmptyState(icon: "doc.text.magnifyingglass",
                           text: model.scanned
                           ? T("Bunday fayl topilmadi", "No files match", "Таких файлов нет")
                           : T("Papka va chegarani tanlab «Qidirish»ni bosing",
                               "Choose a folder and limits, then press Search",
                               "Выберите папку и порог, затем нажмите «Найти»"))
            } else {
                List(model.visible) { f in
                    FileRow(entry: f, toggle: { model.toggle(f.id) })
                }
                .scrollContentBackground(.hidden)
                BottomBar {
                    VStack(alignment: .leading) {
                        Text(T("Tanlangan: \(Format.bytes(model.selectedSize))",
                               "Selected: \(Format.bytes(model.selectedSize))",
                               "Выбрано: \(Format.bytes(model.selectedSize))")).font(.headline)
                        Text(T("\(model.files.count) ta fayl · \(Format.bytes(model.total))",
                               "\(model.files.count) files · \(Format.bytes(model.total))",
                               "\(model.files.count) файлов · \(Format.bytes(model.total))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let m = model.message { Text(m).foregroundColor(Theme.green) }
                    Spacer()
                    if model.message != nil, UndoStore.count > 0 {
                        Button(T("Qaytarish", "Undo", "Отменить")) { model.undo() }.buttonStyle(GhostButtonStyle())
                    }
                    Button(T("Savatga yuborish", "Move to Trash", "В Корзину")) { model.removeSelected() }
                        .buttonStyle(GlowButtonStyle()).disabled(model.selectedSize == 0)
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Dublikatlar

struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    var files: [FileEntry]
    let size: Int64
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

enum DuplicateFinder {
    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var read = 0
        let chunk = 1 << 20
        while true {
            let want = limit.map { min(chunk, $0 - read) } ?? chunk
            if want <= 0 { break }
            guard let data = try? h.read(upToCount: want), !data.isEmpty else { break }
            hasher.update(data: data)
            read += data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func find(root: URL, minSize: Int64) -> [DuplicateGroup] {
        let rootPath = root.path
        var bySize: [Int64: [FileEntry]] = [:]
        var seenInodes = Set<UInt64>()
        FS.walk(rootPath) { path, name, st, isDir in
            if isDir {
                if WalkRules.skipDir(path, name: name, root: rootPath) { return false }
                let ext = (name as NSString).pathExtension
                return ext.isEmpty || !FS.packageExtensions.contains(ext)
            }
            // iCloud'dagi yuklanmagan (dataless) fayllarni o'qimaymiz — aks holda ular yuklab olinadi
            guard !name.hasPrefix("."), (st.st_mode & S_IFMT) == S_IFREG, (st.st_flags & 0x40000000) == 0 else { return true }
            let size = Int64(st.st_size)
            guard size >= minSize else { return true }
            // Hardlink'lar bir xil fayl — dublikat emas
            guard seenInodes.insert(UInt64(st.st_ino)).inserted else { return true }
            bySize[size, default: []].append(FileEntry(url: URL(fileURLWithPath: path), size: size,
                                                       modified: FS.date(st.st_mtimespec), selected: false))
            return true
        }
        var groups: [DuplicateGroup] = []
        for (size, same) in bySize where same.count > 1 {
            var byPartial: [String: [FileEntry]] = [:]
            for f in same { if let h = hash(f.url, limit: 65_536) { byPartial[h, default: []].append(f) } }
            for part in byPartial.values where part.count > 1 {
                var byFull: [String: [FileEntry]] = [:]
                if size <= 65_536 {
                    byFull["small"] = part
                } else {
                    for f in part { if let h = hash(f.url, limit: nil) { byFull[h, default: []].append(f) } }
                }
                for var g in byFull.values where g.count > 1 {
                    // Eng eski nusxa (asl) saqlanadi, qolganlari belgilanadi
                    g.sort { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
                    for i in g.indices { g[i].selected = i != 0 }
                    groups.append(DuplicateGroup(files: g, size: size))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }
}

@MainActor
final class DuplicatesModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var root: URL = FS.home
    @Published var minMB: Int = 1
    @Published var message: String?

    var selectedSize: Int64 { groups.flatMap(\.files).filter(\.selected).reduce(0) { $0 + $1.size } }
    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }

    func scan() {
        guard !scanning else { return }
        scanning = true; message = nil
        let root = root, minBytes: Int64 = minMB == 0 ? 102_400 : Int64(minMB) * 1_048_576
        Task {
            let g = await Task.detached(priority: .userInitiated) { DuplicateFinder.find(root: root, minSize: minBytes) }.value
            self.groups = g; self.scanning = false; self.scanned = true
        }
    }

    func toggle(_ gid: UUID, _ fid: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == gid }),
              let j = groups[i].files.firstIndex(where: { $0.id == fid }) else { return }
        groups[i].files[j].selected.toggle()
        // Kamida bitta nusxa qolishi shart
        if groups[i].files.allSatisfy(\.selected) { groups[i].files[j].selected = false }
    }

    func removeSelected() {
        let sel = groups.flatMap(\.files).filter(\.selected)
        Task {
            let r = await Task.detached { Remover.remove(sel, permanently: false) }.value
            self.scan()
            self.message = T("\(Format.bytes(r.freed)) Savatga yuborildi.",
                             "\(Format.bytes(r.freed)) moved to Trash.",
                             "\(Format.bytes(r.freed)) перемещено в Корзину.")
        }
    }
}

struct DuplicatesView: View {
    @EnvironmentObject var model: DuplicatesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "doc.on.doc", title: T("Dublikatlar", "Duplicates", "Дубликаты"),
                       subtitle: T("SHA-256 bilan bayt-bayt tekshiriladi — eng eski nusxa saqlanadi",
                                   "Verified byte-by-byte with SHA-256 — the oldest copy is kept",
                                   "Проверка по SHA-256 — самая старая копия сохраняется"))
            Card {
                HStack(spacing: 14) {
                    Button {
                        if let u = pickFolder() { model.root = u }
                    } label: {
                        Label(shortPath(model.root), systemImage: "folder")
                    }.buttonStyle(GhostButtonStyle())
                    Picker(T("Kamida", "At least", "Не менее"), selection: $model.minMB) {
                        Text("100 KB").tag(0)
                        Text("1 MB").tag(1)
                        Text("10 MB").tag(10)
                        Text("100 MB").tag(100)
                    }.frame(width: 190)
                    Spacer()
                    Button(model.scanning ? T("Qidirilmoqda…", "Searching…", "Поиск…") : T("Qidirish", "Search", "Найти")) {
                        model.scan()
                    }
                    .buttonStyle(GlowButtonStyle()).disabled(model.scanning)
                }
            }
            if model.scanning {
                ProgressView(T("Fayllar solishtirilmoqda…", "Comparing files…", "Сравнение файлов…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.groups.isEmpty {
                EmptyState(icon: "doc.on.doc",
                           text: model.scanned
                           ? T("Dublikat topilmadi", "No duplicates found", "Дубликатов нет")
                           : T("Papkani tanlab «Qidirish»ni bosing", "Choose a folder and press Search", "Выберите папку и нажмите «Найти»"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.groups) { g in
                            Card {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(T("\(g.files.count) ta nusxa · har biri \(Format.bytes(g.size))",
                                               "\(g.files.count) copies · \(Format.bytes(g.size)) each",
                                               "\(g.files.count) копии · по \(Format.bytes(g.size))")).font(.headline)
                                        Spacer()
                                        Text(T("Ortiqcha: \(Format.bytes(g.wasted))",
                                               "Wasted: \(Format.bytes(g.wasted))",
                                               "Лишнее: \(Format.bytes(g.wasted))")).foregroundColor(Theme.orange)
                                    }
                                    ForEach(g.files) { f in
                                        FileRow(entry: f, toggle: { model.toggle(g.id, f.id) })
                                    }
                                }
                            }
                        }
                    }
                }
                BottomBar {
                    VStack(alignment: .leading) {
                        Text(T("Tanlangan: \(Format.bytes(model.selectedSize))",
                               "Selected: \(Format.bytes(model.selectedSize))",
                               "Выбрано: \(Format.bytes(model.selectedSize))")).font(.headline)
                        Text(T("\(model.groups.count) guruh · ortiqcha \(Format.bytes(model.wasted))",
                               "\(model.groups.count) groups · \(Format.bytes(model.wasted)) wasted",
                               "\(model.groups.count) групп · лишнее \(Format.bytes(model.wasted))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let m = model.message { Text(m).foregroundColor(Theme.green) }
                    Spacer()
                    Button(T("Savatga yuborish", "Move to Trash", "В Корзину")) { model.removeSelected() }
                        .buttonStyle(GlowButtonStyle()).disabled(model.selectedSize == 0)
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Dasturchi keraksizlari (node_modules va h.k.)

enum DevScanner {
    static func scan(root: URL) -> [FileEntry] {
        let rootPath = root.path
        let monthAgo = Date().addingTimeInterval(-30 * 86400)
        let lib = FS.home.path + "/Library"
        var out: [FileEntry] = []
        FS.walk(rootPath) { path, name, st, isDir in
            guard isDir, path != rootPath else { return true }
            if path == lib || name == ".Trash" || name == ".git" || path.hasPrefix("/System") { return false }
            let parent = (path as NSString).deletingLastPathComponent
            func has(_ n: String) -> Bool { FileManager.default.fileExists(atPath: parent + "/" + n) }
            var kind: String?
            switch name {
            case "node_modules": if has("package.json") { kind = "Node.js" }
            case "Pods": if has("Podfile") { kind = "CocoaPods" }
            case "venv", ".venv", "env":
                if FileManager.default.fileExists(atPath: path + "/pyvenv.cfg") { kind = "Python venv" }
            case "target": if has("Cargo.toml") { kind = "Rust" }
            case ".build": if has("Package.swift") { kind = "SwiftPM" }
            case "build": if has("build.gradle") || has("build.gradle.kts") { kind = "Gradle" }
            case ".next", ".nuxt", ".parcel-cache", ".turbo", ".svelte-kit", ".angular":
                if has("package.json") { kind = "JS build" }
            case "__pycache__": kind = "Python cache"
            case "DerivedData": kind = "Xcode"
            default: break
            }
            if let kind {
                let url = URL(fileURLWithPath: path)
                let size = FS.allocatedSize(of: url)
                let mod = FS.date(st.st_mtimespec)
                if size > 0 {
                    out.append(FileEntry(url: url, size: size, modified: mod,
                                         selected: mod < monthAgo,
                                         note: "\(kind) · \(shortPath(URL(fileURLWithPath: parent)))"))
                }
                return false
            }
            if name.hasPrefix(".") { return false }
            let ext = (name as NSString).pathExtension
            return ext.isEmpty || !FS.packageExtensions.contains(ext)
        }
        return out.sorted { $0.size > $1.size }
    }
}

@MainActor
final class DevModel: ObservableObject {
    @Published var items: [FileEntry] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var root: URL = FS.home
    @Published var message: String?

    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var total: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !scanning else { return }
        scanning = true; message = nil
        let root = root
        Task {
            let r = await Task.detached(priority: .userInitiated) { DevScanner.scan(root: root) }.value
            self.items = r; self.scanning = false; self.scanned = true
        }
    }

    func toggle(_ id: UUID) { if let i = items.firstIndex(where: { $0.id == id }) { items[i].selected.toggle() } }

    func removeSelected() {
        let sel = items.filter(\.selected)
        Task {
            let r = await Task.detached { Remover.remove(sel, permanently: true) }.value
            let failed = Set(r.failed)
            self.items.removeAll { $0.selected && !failed.contains($0.url) }
            self.message = T("\(Format.bytes(r.freed)) bo'shatildi. Qayta kerak bo'lsa: npm install / pod install.",
                             "\(Format.bytes(r.freed)) freed. Need it again? npm install / pod install.",
                             "Освобождено \(Format.bytes(r.freed)). Понадобится снова — npm install / pod install.")
        }
    }
}

struct DevView: View {
    @EnvironmentObject var model: DevModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "chevron.left.forwardslash.chevron.right",
                       title: T("Dasturchi keraksizlari", "Developer Junk", "Мусор разработчика"),
                       subtitle: T("node_modules, Pods, venv, Rust target, .build — 30 kundan eski loyihalar avtomatik belgilanadi",
                                   "node_modules, Pods, venv, Rust target, .build — projects untouched for 30+ days are preselected",
                                   "node_modules, Pods, venv, Rust target, .build — проекты старше 30 дней выбраны автоматически"))
            Card {
                HStack {
                    Button {
                        if let u = pickFolder() { model.root = u }
                    } label: {
                        Label(shortPath(model.root), systemImage: "folder")
                    }.buttonStyle(GhostButtonStyle())
                    Spacer()
                    Button(model.scanning ? T("Qidirilmoqda…", "Searching…", "Поиск…") : T("Qidirish", "Search", "Найти")) {
                        model.scan()
                    }
                    .buttonStyle(GlowButtonStyle()).disabled(model.scanning)
                }
            }
            if model.scanning {
                ProgressView(T("Loyihalar qidirilmoqda…", "Looking for projects…", "Поиск проектов…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty {
                EmptyState(icon: "hammer",
                           text: model.scanned
                           ? T("Hech narsa topilmadi", "Nothing found", "Ничего не найдено")
                           : T("«Qidirish»ni bosing", "Press Search", "Нажмите «Найти»"))
            } else {
                List(model.items) { f in FileRow(entry: f, toggle: { model.toggle(f.id) }) }
                    .scrollContentBackground(.hidden)
                BottomBar {
                    VStack(alignment: .leading) {
                        Text(T("Tanlangan: \(Format.bytes(model.selectedSize))",
                               "Selected: \(Format.bytes(model.selectedSize))",
                               "Выбрано: \(Format.bytes(model.selectedSize))")).font(.headline)
                        Text(T("Jami: \(Format.bytes(model.total))", "Total: \(Format.bytes(model.total))",
                               "Всего: \(Format.bytes(model.total))")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let m = model.message { Text(m).foregroundColor(Theme.green) }
                    Spacer()
                    Button(T("O'chirish", "Delete", "Удалить")) { model.removeSelected() }
                        .buttonStyle(GlowButtonStyle()).disabled(model.selectedSize == 0)
                }
            }
        }
        .padding(24)
    }
}
