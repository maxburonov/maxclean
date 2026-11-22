import SwiftUI
import AppKit

// MARK: - Model

struct JunkCategory: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let icon: String
    let detail: String
    var items: [FileEntry]
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
}

struct JunkSpec: Sendable {
    enum Mode: Sendable {
        case children            // ildiz ichidagi har bir element
        case whole               // ildizning o'zi
        case extensions([String]) // faqat shu kengaytmali fayllar
        case electronCaches      // har bir ilova papkasidagi Cache/GPUCache...
        case namePrefix([String]) // nomi shu so'z bilan boshlanadigan elementlar
    }
    let name: String
    let icon: String
    let detail: String
    let roots: [String]
    let mode: Mode
    var defaultSelected = true
    var skip: Set<String> = []
}

extension JunkSpec {
    static let electronCacheNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "GrShaderCache", "ShaderCache", "CachedData", "CachedExtensionVSIXs", "Crashpad",
        "logs"
    ]

    static var all: [JunkSpec] { [
        JunkSpec(name: T("Foydalanuvchi keshlari", "User caches", "Кэши пользователя"), icon: "archivebox",
                 detail: T("Ilovalar qayta yaratadigan vaqtinchalik fayllar", "Temporary files apps recreate on their own", "Временные файлы, которые приложения создают заново"),
                 roots: ["~/Library/Caches"], mode: .children,
                 skip: ["com.apple.bird", "CloudKit", "com.apple.HomeKit", "FamilyCircle",
                        "com.apple.ap.adprivacyd", "uz.max.clean", "com.apple.akd",
                        "com.anthropic.claudefordesktop", "claude-cli-nodejs"]),
        JunkSpec(name: T("Claude va AI ilovalar", "Claude & AI apps", "Claude и AI-приложения"), icon: "brain",
                 detail: T("Claude Desktop keshi va VM obrazlari (kerak bo'lsa qayta yuklanadi)", "Claude Desktop cache and VM images (re-downloaded when needed)", "Кэш Claude Desktop и образы VM (скачаются заново при необходимости)"),
                 roots: ["~/Library/Application Support/Claude/vm_bundles",
                         "~/Library/Application Support/Claude/Cache",
                         "~/Library/Application Support/Claude/Code Cache",
                         "~/Library/Application Support/Claude/GPUCache",
                         "~/Library/Application Support/Claude/logs",
                         "~/Library/Logs/Claude",
                         "~/Library/Caches/com.anthropic.claudefordesktop",
                         "~/Library/Caches/claude-cli-nodejs",
                         "~/Library/Application Support/ChatGPT/Cache"],
                 mode: .whole),
        JunkSpec(name: T("Electron ilovalar keshi", "Electron app caches", "Кэш Electron-приложений"), icon: "bolt.horizontal.circle",
                 detail: T("Slack, Discord, VS Code, Telegram, Figma va boshqalar keshi", "Slack, Discord, VS Code, Telegram, Figma and more", "Slack, Discord, VS Code, Telegram, Figma и другие"),
                 roots: ["~/Library/Application Support"], mode: .electronCaches,
                 skip: ["Claude", "ChatGPT", "MaxClean"]),
        JunkSpec(name: T("Foydalanuvchi loglari", "User logs", "Логи пользователя"), icon: "doc.text",
                 detail: T("Ilova jurnallari va crash hisobotlari", "App logs and crash reports", "Журналы приложений и отчёты о сбоях"),
                 roots: ["~/Library/Logs"], mode: .children, skip: ["Claude"]),
        JunkSpec(name: T("Tizim loglari", "System logs", "Системные логи"), icon: "server.rack",
                 detail: T("Diagnostika hisobotlari", "Diagnostic reports", "Диагностические отчёты"),
                 roots: ["/Library/Logs/DiagnosticReports"], mode: .children),
        JunkSpec(name: T("Xcode keraksizlari", "Xcode junk", "Мусор Xcode"), icon: "hammer",
                 detail: T("DerivedData, eski qurilma fayllari, simulator keshi", "DerivedData, old device support, simulator cache", "DerivedData, старые файлы устройств, кэш симулятора"),
                 roots: ["~/Library/Developer/Xcode/DerivedData",
                         "~/Library/Developer/Xcode/iOS DeviceSupport",
                         "~/Library/Developer/Xcode/macOS DeviceSupport",
                         "~/Library/Developer/Xcode/watchOS DeviceSupport"],
                 mode: .children),
        JunkSpec(name: T("Simulator keshi", "Simulator cache", "Кэш симулятора"), icon: "iphone",
                 detail: T("CoreSimulator keshlari", "CoreSimulator caches", "Кэши CoreSimulator"),
                 roots: ["~/Library/Developer/CoreSimulator/Caches"], mode: .whole),
        JunkSpec(name: T("Paket menejerlari", "Package managers", "Пакетные менеджеры"), icon: "shippingbox",
                 detail: T("npm, pnpm, Gradle, pip, Go va boshqa yuklab olish keshlari", "npm, pnpm, Gradle, pip, Go and other download caches", "Кэши загрузок npm, pnpm, Gradle, pip, Go и др."),
                 roots: ["~/.npm/_cacache", "~/.pnpm-store", "~/.gradle/caches",
                         "~/.cache/pip", "~/.cache/huggingface/xet", "~/go/pkg/mod/cache",
                         "~/.cargo/registry/cache", "~/.bun/install/cache"],
                 mode: .whole),
        JunkSpec(name: T("Mail biriktirmalari", "Mail attachments", "Вложения Mail"), icon: "envelope",
                 detail: T("Mail yuklab olgan nusxalar (asl xatlar qoladi)", "Copies downloaded by Mail (emails stay intact)", "Копии, скачанные Mail (письма остаются)"),
                 roots: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
                 mode: .children),
        JunkSpec(name: T("O'rnatuvchi fayllar", "Installers", "Установщики"), icon: "shippingbox.circle",
                 detail: T(".dmg / .pkg / .xip — Downloads papkasida", ".dmg / .pkg / .xip in Downloads", ".dmg / .pkg / .xip в Загрузках"),
                 roots: ["~/Downloads"], mode: .extensions(["dmg", "pkg", "xip", "mpkg"]),
                 defaultSelected: false),
        JunkSpec(name: T("iOS zaxira nusxalari", "iOS backups", "Резервные копии iOS"), icon: "externaldrive.badge.icloud",
                 detail: T("iPhone/iPad backup'lari — ehtiyot bo'ling", "iPhone/iPad backups — be careful", "Бэкапы iPhone/iPad — осторожно"),
                 roots: ["~/Library/Application Support/MobileSync/Backup"], mode: .children,
                 defaultSelected: false),
        JunkSpec(name: T("Eski macOS o'rnatuvchilari", "Old macOS installers", "Старые установщики macOS"), icon: "applelogo",
                 detail: T("«Install macOS …» ilovalari — har biri 12–15 GB, kerak bo'lsa qayta yuklanadi",
                           "\"Install macOS …\" apps — 12–15 GB each, re-downloadable",
                           "Приложения «Установка macOS …» — по 12–15 ГБ, можно скачать снова"),
                 roots: ["/Applications"], mode: .namePrefix(["Install macOS"]), defaultSelected: false),
        JunkSpec(name: T("GitHub build-server qoldiqlari", "GitHub runner leftovers", "Остатки GitHub runner"), icon: "server.rack",
                 detail: T("actions-runner'ning ish papkalari va loglari — build ketmayotganda o'chirish xavfsiz",
                           "actions-runner work folders and logs — safe to delete when no job is running",
                           "Рабочие папки и логи actions-runner — удалять, когда сборка не идёт"),
                 roots: ["~/actions-runner/_work", "~/actions-runner/_diag"], mode: .children,
                 defaultSelected: false, skip: ["_tool", "_actions"]),
        JunkSpec(name: T("Python paket arxivlari", "Python package archives", "Архивы Python-пакетов"), icon: "cube.box",
                 detail: T("conda yuklab olgan .conda / .tar.bz2 arxivlari (o'rnatilganlar o'chmaydi)",
                           "Downloaded conda .conda / .tar.bz2 archives (installed packages stay)",
                           "Скачанные архивы conda .conda / .tar.bz2 (установленное остаётся)"),
                 roots: ["~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/miniforge3/pkgs", "~/.conda/pkgs"],
                 mode: .extensions(["conda", "bz2"])),
        JunkSpec(name: T("AI modellar keshi", "AI model caches", "Кэш AI-моделей"), icon: "cpu",
                 detail: T("Hugging Face va PyTorch yuklab olgan modellar — kerak bo'lsa qayta yuklanadi (katta!)",
                           "Models downloaded by Hugging Face and PyTorch — re-downloaded when needed (large!)",
                           "Модели Hugging Face и PyTorch — скачаются снова при необходимости (много места!)"),
                 roots: ["~/.cache/huggingface/hub", "~/.cache/torch"], mode: .children,
                 defaultSelected: false),
        JunkSpec(name: T("Savat", "Trash", "Корзина"), icon: "trash",
                 detail: T("Savatdagi fayllar", "Files in the Trash", "Файлы в Корзине"),
                 roots: ["~/.Trash"], mode: .children),
        // Tashqi disklar (masalan T9) savati — ichki diskda joy bo'shatmaydi, shuning uchun avtomatik tanlanmaydi
        JunkSpec(name: T("Tashqi disklar savati", "External disks' Trash", "Корзина внешних дисков"), icon: "externaldrive",
                 detail: T("T9 kabi disklardagi Savat — o'sha diskda joy bo'shatadi",
                           "Trash on disks like T9 — frees space on that disk",
                           "Корзина на дисках вроде T9 — освобождает место на них"),
                 roots: Array(TrashInfo.locations().dropFirst()).map { $0.path }, mode: .children,
                 defaultSelected: false)
    ] }
}

/// Aqlli tozalash uchun kontekst: qaysi ilovalar ochiq va foydalanuvchi nimalarni qoldirishni afzal ko'radi.
struct SmartContext: Sendable {
    var runningIDs: Set<String> = []
    var runningNames: Set<String> = []
    var keep: Set<String> = []
    static let empty = SmartContext()

    /// Asosiy oqimda chaqiring.
    @MainActor static func current() -> SmartContext {
        var c = SmartContext()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier?.lowercased() { c.runningIDs.insert(id) }
            if let n = app.localizedName?.lowercased(), n.count >= 3 {
                c.runningNames.insert(n)
                // "google chrome" → "google" (Chrome keshi ~/Library/Caches/Google ichida)
                if let first = n.split(separator: " ").first.map(String.init), first.count >= 4 { c.runningNames.insert(first) }
            }
        }
        c.keep = Set(UserDefaults.standard.stringArray(forKey: "junkKeep") ?? [])
        return c
    }

    /// Element hozir ochiq ilovaga tegishlimi? Faqat elementning o'z nomi va ilova papkasi tekshiriladi.
    func inUse(_ url: URL, appFolder: String? = nil) -> String? {
        let comps = [url.lastPathComponent.lowercased(), appFolder?.lowercased()].compactMap { $0 }
        for c in comps {
            if let id = runningIDs.first(where: { c.contains($0) }) { return id }
            let base = (c as NSString).deletingPathExtension
            if runningNames.contains(c) || runningNames.contains(base) { return base }
        }
        return nil
    }
}

enum JunkScanner {
    static func scan(_ spec: JunkSpec, ctx: SmartContext = .empty) -> JunkCategory {
        // GitHub runner hozir build qilayotgan bo'lsa — uning papkalariga umuman tegmaymiz
        if spec.roots.contains(where: { $0.hasPrefix("~/actions-runner") }),
           Shell.run("/usr/bin/pgrep", ["-x", "Runner.Worker"]).status == 0 {
            return JunkCategory(name: spec.name, icon: spec.icon, detail: spec.detail, items: [])
        }
        var items: [FileEntry] = []
        let dayAgo = Date().addingTimeInterval(-86_400)
        var isCacheLike = spec.roots.contains { $0.contains("Cache") || $0.contains("/Logs") }
        if case .electronCaches = spec.mode { isCacheLike = true }
        func add(_ url: URL, note: String? = nil, appFolder: String? = nil) {
            guard !Safety.isProtected(url), FS.fm.isDeletableFile(atPath: url.path) else { return }
            let s = FS.allocatedSize(of: url)
            guard s > 0 else { return }
            let mod = FS.modified(url)
            var selected = spec.defaultSelected
            var hint: String?
            // Aqlli qoidalar — xavfsizlik birinchi
            if ctx.keep.contains(url.path) {
                selected = false
                hint = T("Siz qoldirgansiz", "You kept this", "Вы оставили")
            } else if let app = ctx.inUse(url, appFolder: appFolder) {
                selected = false
                hint = T("Ilova ochiq (\(app)) — yopilgach tozalang", "App is running (\(app)) — clean after quitting",
                         "Приложение открыто (\(app)) — очистите после закрытия")
            } else if isCacheLike, let m = mod, m > dayAgo, s < 200_000_000 {
                selected = false
                hint = T("Hozir ishlatilmoqda — baribir qayta yaratiladi", "In active use — would be recreated right away",
                         "Используется сейчас — сразу создастся снова")
            }
            items.append(FileEntry(url: url, size: s, modified: mod, selected: selected, note: note, hint: hint))
        }
        for r in spec.roots {
            let root = FS.expand(r)
            guard FS.exists(root) else { continue }
            switch spec.mode {
            case .whole:
                add(root, note: root.deletingLastPathComponent().path,
                    appFolder: root.deletingLastPathComponent().lastPathComponent)
            case .children:
                for c in FS.children(root) where !spec.skip.contains(c.lastPathComponent) && c.lastPathComponent != ".DS_Store" {
                    add(c)
                }
            case .extensions(let exts):
                for c in FS.children(root) where exts.contains(c.pathExtension.lowercased()) {
                    add(c)
                }
            case .namePrefix(let prefixes):
                for c in FS.children(root) where prefixes.contains(where: { c.lastPathComponent.hasPrefix($0) }) {
                    add(c)
                }
            case .electronCaches:
                for app in FS.children(root) where FS.isDir(app) && !spec.skip.contains(app.lastPathComponent) {
                    for sub in FS.children(app) where JunkSpec.electronCacheNames.contains(sub.lastPathComponent) {
                        add(sub, note: app.lastPathComponent, appFolder: app.lastPathComponent)
                    }
                    // Chromium profillari: Default/Cache va h.k.
                    let def = app.appendingPathComponent("Default")
                    if FS.isDir(def) {
                        for sub in FS.children(def) where JunkSpec.electronCacheNames.contains(sub.lastPathComponent) {
                            add(sub, note: app.lastPathComponent + " / Default", appFolder: app.lastPathComponent)
                        }
                    }
                }
            }
        }
        items.sort { $0.size > $1.size }
        return JunkCategory(name: spec.name, icon: spec.icon, detail: spec.detail, items: items)
    }

    private final class Collector: @unchecked Sendable {
        var results: [JunkCategory?]
        var done = 0
        let lock = NSLock()
        init(_ n: Int) { results = Array(repeating: nil, count: n) }
        func put(_ i: Int, _ c: JunkCategory) -> Int {
            lock.lock(); defer { lock.unlock() }
            results[i] = c; done += 1
            return done
        }
    }

    static func scanAll(ctx: SmartContext = .empty, progress: (@Sendable (Double) -> Void)? = nil) -> [JunkCategory] {
        let specs = JunkSpec.all
        let box = Collector(specs.count)
        DispatchQueue.concurrentPerform(iterations: specs.count) { i in
            let d = box.put(i, scan(specs[i], ctx: ctx))
            progress?(Double(d) / Double(specs.count))
        }
        return box.results.compactMap { $0 }.filter { !$0.items.isEmpty }
    }
}

@MainActor
final class JunkModel: ObservableObject {
    @Published var categories: [JunkCategory] = []
    @Published var scanning = false
    @Published var cleaning = false
    @Published var scannedOnce = false
    @Published var message: String?
    @Published var expanded: Set<UUID> = []
    @Published var progress: Double = 0
    @Published var lastFreed: Int64 = 0
    /// Tozalash tugagach bir necha soniya "muvaffaqiyat" animatsiyasini ko'rsatish uchun.
    @Published var justCleaned = false

    var total: Int64 { categories.reduce(0) { $0 + $1.total } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }

    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard !scanning else { return nil }
        scanning = true
        message = nil
        progress = 0
        return Task {
            let ctx = SmartContext.current()
            let cats = await Task.detached(priority: .userInitiated) {
                JunkScanner.scanAll(ctx: ctx) { p in Task { @MainActor in self.progress = max(self.progress, p) } }
            }.value
            self.categories = cats
            self.scanning = false
            self.scannedOnce = true
        }
    }

    func setCategory(_ id: UUID, _ on: Bool) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        for j in categories[i].items.indices { categories[i].items[j].selected = on }
    }

    /// Foydalanuvchi belgini olib tashlasa — eslab qolamiz (keyingi skanerlashda ham tanlanmaydi).
    func toggleItem(_ cid: UUID, _ iid: UUID) {
        guard let i = categories.firstIndex(where: { $0.id == cid }),
              let j = categories[i].items.firstIndex(where: { $0.id == iid }) else { return }
        categories[i].items[j].selected.toggle()
        let item = categories[i].items[j]
        var keep = Set(UserDefaults.standard.stringArray(forKey: "junkKeep") ?? [])
        if item.selected {
            keep.remove(item.url.path)
            categories[i].items[j].hint = nil
        } else {
            keep.insert(item.url.path)
        }
        UserDefaults.standard.set(Array(keep), forKey: "junkKeep")
    }

    /// "Siz qoldirgansiz" ro'yxatini tozalash.
    static func resetKeep() { UserDefaults.standard.removeObject(forKey: "junkKeep") }

    @discardableResult
    func clean(rescan: Bool = true) -> Task<Void, Never>? {
        let entries = categories.flatMap { $0.items.filter(\.selected) }
        guard !entries.isEmpty else { return nil }
        let permanent = UserDefaults.standard.object(forKey: "junkPermanent") as? Bool ?? true
        // O'rnatuvchilar va iOS backup'lar har doim faqat Savatga (qaytarib olish mumkin)
        let trashOnly = ["~/Downloads", "~/Library/Application Support/MobileSync/Backup"].map { FS.expand($0).path + "/" }
            + ["/Applications/Install macOS"]
        cleaning = true
        return Task {
            let r = await Task.detached(priority: .userInitiated) { () -> Remover.Result in
                // Savatdagi narsalar — doim butunlay o'chiriladi (ularni yana Savatga yuborib bo'lmaydi)
                let trashLocs = TrashInfo.locations().map { $0.path + "/" }
                let inTrash = entries.filter { e in trashLocs.contains { e.url.path.hasPrefix($0) } }
                let rest = entries.filter { e in !trashLocs.contains { e.url.path.hasPrefix($0) } }
                let normal = rest.filter { e in !trashOnly.contains { e.url.path.hasPrefix($0) } }
                let safe = rest.filter { e in trashOnly.contains { e.url.path.hasPrefix($0) } }
                var a = Remover.remove(normal, permanently: permanent)
                let t = Remover.remove(inTrash, permanently: true)
                a.freed += t.freed; a.removed += t.removed; a.failed += t.failed; a.permanentFreed += t.permanentFreed
                let b = Remover.remove(safe, permanently: false, appendUndo: !permanent && !normal.isEmpty)
                a.freed += b.freed; a.removed += b.removed; a.failed += b.failed; a.permanentFreed += b.permanentFreed
                return a
            }.value
            self.cleaning = false
            self.lastFreed = r.freed
            withAnimation(.spring()) { self.justCleaned = true }
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                withAnimation(.easeInOut) { self.justCleaned = false }
            }
            let toTrash = r.freed - r.permanentFreed
            var text = toTrash > 0
                ? T("\(Format.bytes(r.permanentFreed)) bo'shatildi, \(Format.bytes(toTrash)) Savatga yuborildi.",
                    "\(Format.bytes(r.permanentFreed)) freed, \(Format.bytes(toTrash)) moved to Trash.",
                    "Освобождено \(Format.bytes(r.permanentFreed)), \(Format.bytes(toTrash)) — в Корзине.")
                : T("\(Format.bytes(r.freed)) bo'shatildi (\(r.removed) ta element).", "\(Format.bytes(r.freed)) freed (\(r.removed) items).", "Освобождено \(Format.bytes(r.freed)) (\(r.removed) элем.).")
            if !r.failed.isEmpty { text += T(" \(r.failed.count) tasi o'chmadi (band yoki ruxsat yo'q).", " \(r.failed.count) couldn't be removed (in use or no permission).", " \(r.failed.count) не удалено (занято или нет доступа).") }
            self.message = text
            self.scanning = false
            if rescan { self.scan() }
        }
    }
}

// MARK: - View

struct JunkView: View {
    @EnvironmentObject var model: JunkModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "trash.circle", title: T("Tizim keraksizlari", "System Junk", "Системный мусор"),
                       subtitle: T("Kesh, log, Claude/Electron keshi, Xcode va paket menejerlari", "Caches, logs, Claude/Electron caches, Xcode and package managers", "Кэши, логи, кэш Claude/Electron, Xcode и пакетные менеджеры")) {
                Button(model.scanning ? T("Skanerlanmoqda…", "Scanning…", "Сканирование…") : T("Qayta skanerlash", "Rescan", "Пересканировать")) { model.scan() }
                    .buttonStyle(GhostButtonStyle()).disabled(model.scanning)
            }

            if let m = model.message {
                Label(m, systemImage: "checkmark.seal.fill").foregroundColor(Theme.green)
            }

            if !model.scannedOnce && !model.scanning {
                VStack(spacing: 18) {
                    Spacer()
                    BigScanButton(title: T("Skanerlash", "Scan", "Сканировать"), busy: false) { model.scan() }
                    Text(T("Mac'dagi keraksiz fayllarni topamiz", "Let's find the junk on your Mac", "Найдём мусор на вашем Mac")).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else if model.scanning && model.categories.isEmpty {
                VStack(spacing: 18) {
                    Spacer()
                    ScanProgressRing(progress: model.progress)
                    Text(T("Skanerlanmoqda…", "Scanning…", "Сканирование…")).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else if model.categories.isEmpty {
                EmptyState(icon: "checkmark.seal", text: T("Hammasi toza! Keraksiz fayl topilmadi.", "All clean! No junk found.", "Всё чисто! Мусор не найден."))
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.categories) { cat in
                            categoryCard(cat)
                        }
                    }
                }
                BottomBar {
                    VStack(alignment: .leading) {
                        Text(T("Tanlangan: \(Format.bytes(model.selectedSize))", "Selected: \(Format.bytes(model.selectedSize))", "Выбрано: \(Format.bytes(model.selectedSize))")).font(.headline)
                        Text(T("Jami topildi: \(Format.bytes(model.total))", "Total found: \(Format.bytes(model.total))", "Всего найдено: \(Format.bytes(model.total))")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.cleaning ? T("Tozalanmoqda…", "Cleaning…", "Очистка…") : T("Tozalash", "Clean", "Очистить")) { model.clean() }
                        .buttonStyle(GlowButtonStyle())
                        .disabled(model.cleaning || model.selectedSize == 0)
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder
    func categoryCard(_ cat: JunkCategory) -> some View {
        let isOpen = model.expanded.contains(cat.id)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { !cat.items.isEmpty && cat.items.allSatisfy(\.selected) },
                        set: { model.setCategory(cat.id, $0) }))
                        .toggleStyle(.checkbox).labelsHidden()
                    Image(systemName: cat.icon).font(.title2).foregroundStyle(Theme.accentGradient).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cat.name).font(.headline)
                        Text(cat.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Format.bytes(cat.total)).font(.system(.title3, design: .rounded).weight(.semibold))
                    Button {
                        if isOpen { model.expanded.remove(cat.id) } else { model.expanded.insert(cat.id) }
                    } label: {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    }.buttonStyle(.borderless)
                }
                if isOpen {
                    Divider().opacity(0.3)
                    ForEach(cat.items) { item in
                        FileRow(entry: item, toggle: { model.toggleItem(cat.id, item.id) })
                    }
                }
            }
        }
    }
}
