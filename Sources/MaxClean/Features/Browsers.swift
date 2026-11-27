import SwiftUI
import AppKit

// MARK: - Brauzer tozalash
//
// Kesh — xavfsiz (sahifalar qayta yuklanadi). Tarix va cookie'lar — faqat foydalanuvchi tanlasa
// (cookie o'chsa saytlardan chiqib ketiladi). Ochiq brauzerga tegilmaydi.

struct BrowserDef: Sendable {
    let id: String
    let name: String
    let bundleID: String
    /// Chromium oilasi: ~/Library/Application Support ichidagi ma'lumot papkasi
    let chromiumData: String?
    /// ~/Library/Caches ichidagi kesh papkasi
    let cacheDir: String?
    /// Xuddi shu profil/kesh papkasini ishlatadigan boshqa variantlar (Developer Edition va h.k.)
    var alsoRunning: [String] = []
    var allBundleIDs: [String] { [bundleID] + alsoRunning }

    static let all: [BrowserDef] = [
        BrowserDef(id: "safari", name: "Safari", bundleID: "com.apple.Safari", chromiumData: nil, cacheDir: "com.apple.Safari",
                   alsoRunning: ["com.apple.SafariTechnologyPreview"]),
        BrowserDef(id: "chrome", name: "Google Chrome", bundleID: "com.google.Chrome", chromiumData: "Google/Chrome", cacheDir: "Google/Chrome"),
        BrowserDef(id: "edge", name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", chromiumData: "Microsoft Edge", cacheDir: "Microsoft Edge"),
        BrowserDef(id: "brave", name: "Brave", bundleID: "com.brave.Browser", chromiumData: "BraveSoftware/Brave-Browser", cacheDir: "BraveSoftware/Brave-Browser"),
        BrowserDef(id: "opera", name: "Opera", bundleID: "com.operasoftware.Opera", chromiumData: "com.operasoftware.Opera", cacheDir: "com.operasoftware.Opera"),
        BrowserDef(id: "arc", name: "Arc", bundleID: "company.thebrowser.Browser", chromiumData: "Arc/User Data", cacheDir: "Arc/User Data"),
        BrowserDef(id: "yandex", name: "Yandex", bundleID: "ru.yandex.desktop.yandex-browser", chromiumData: "Yandex/YandexBrowser", cacheDir: "Yandex/YandexBrowser"),
        BrowserDef(id: "firefox", name: "Firefox", bundleID: "org.mozilla.firefox", chromiumData: nil, cacheDir: "Firefox",
                   alsoRunning: ["org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"])
    ]

    /// Junk "Foydalanuvchi keshlari" va Electron keshidan chiqarib tashlanadigan nomlar (ikki marta sanalmasin)
    static let cacheTopNames: Set<String> = ["Microsoft Edge", "BraveSoftware", "com.operasoftware.Opera",
                                              "Arc", "Yandex", "Firefox", "com.apple.Safari"]
}

enum BrowserPart: String, CaseIterable, Sendable {
    case cache, history, cookies
    var title: String {
        switch self {
        case .cache: return T("Kesh", "Cache", "Кэш")
        case .history: return T("Tarix", "History", "История")
        case .cookies: return T("Cookie'lar", "Cookies", "Cookies")
        }
    }
    var hint: String {
        switch self {
        case .cache: return T("Xavfsiz — sahifalar qayta yuklanadi", "Safe — pages reload", "Безопасно — страницы загрузятся снова")
        case .history: return T("Ko'rilgan saytlar va yuklab olishlar ro'yxati", "Visited sites and downloads list",
                                "Посещённые сайты и список загрузок")
        case .cookies: return T("Saytlardan chiqib ketasiz", "You'll be signed out of sites", "Вы выйдете из аккаунтов на сайтах")
        }
    }
}

struct BrowserScan: Identifiable, Sendable {
    var id: String { def.id }
    let def: BrowserDef
    var parts: [BrowserPart: [FileEntry]] = [:]
    func size(_ p: BrowserPart) -> Int64 { (parts[p] ?? []).reduce(0) { $0 + $1.size } }
    var total: Int64 { BrowserPart.allCases.reduce(0) { $0 + size($1) } }
}

enum BrowserScanner {
    static func installed(_ d: BrowserDef) -> Bool {
        d.allBundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    static func isRunning(_ d: BrowserDef) -> Bool {
        d.allBundleIDs.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    private static func entries(_ urls: [URL]) -> [FileEntry] {
        urls.filter { FS.exists($0) && !Safety.isProtected($0) }
            .compactMap { u in
                let s = FS.allocatedSize(of: u)
                return s > 0 ? FileEntry(url: u, size: s, modified: FS.modified(u), selected: true) : nil
            }
    }

    static func scan(_ d: BrowserDef) -> BrowserScan {
        var r = BrowserScan(def: d)
        let lib = FS.home.appendingPathComponent("Library")
        var cache: [URL] = []
        var history: [URL] = []
        var cookies: [URL] = []

        if let c = d.cacheDir { cache.append(lib.appendingPathComponent("Caches/\(c)")) }

        if let data = d.chromiumData {
            let root = lib.appendingPathComponent("Application Support/\(data)")
            for app in ["GrShaderCache", "ShaderCache", "component_crx_cache", "GraphiteDawnCache"] {
                cache.append(root.appendingPathComponent(app))
            }
            var profiles = FS.children(root).filter {
                let n = $0.lastPathComponent
                return n == "Default" || n.hasPrefix("Profile ") || n == "Guest Profile"
            }
            // Opera profil fayllarini to'g'ridan-to'g'ri ildizda saqlaydi
            if profiles.isEmpty, FS.exists(root.appendingPathComponent("Preferences")) { profiles = [root] }
            for p in profiles {
                for n in ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "Service Worker/CacheStorage",
                          "Service Worker/ScriptCache"] {
                    cache.append(p.appendingPathComponent(n))
                }
                for n in ["History", "History-journal", "Visited Links", "Top Sites", "Top Sites-journal", "Shortcuts",
                          "Shortcuts-journal", "Network Action Predictor"] {
                    history.append(p.appendingPathComponent(n))
                }
                for n in ["Cookies", "Cookies-journal", "Network/Cookies", "Network/Cookies-journal"] {
                    cookies.append(p.appendingPathComponent(n))
                }
            }
        }

        if d.id == "safari" {
            cache += FS.children(lib.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Caches"))
                .filter { $0.lastPathComponent != ".DS_Store" }
            for n in ["History.db", "History.db-wal", "History.db-shm", "History.db-lock"] {
                history.append(lib.appendingPathComponent("Safari/\(n)"))
            }
            cookies.append(lib.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"))
            cookies.append(lib.appendingPathComponent("Cookies/Cookies.binarycookies"))
        }

        if d.id == "firefox" {
            // Tarixni o'chirmaymiz: places.sqlite ichida xatcho'plar ham bor
            for p in FS.children(lib.appendingPathComponent("Application Support/Firefox/Profiles")) {
                cookies.append(p.appendingPathComponent("cookies.sqlite"))
                cookies.append(p.appendingPathComponent("cookies.sqlite-wal"))
            }
        }

        r.parts[.cache] = entries(cache)
        r.parts[.history] = entries(history)
        r.parts[.cookies] = entries(cookies)
        return r
    }

    static func scanAll() -> [BrowserScan] {
        BrowserDef.all.filter(installed).map(scan).filter { $0.total > 0 }
    }
}

@MainActor
final class BrowsersModel: ObservableObject {
    @Published var browsers: [BrowserScan] = []
    @Published var running: Set<String> = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var message: String?
    /// browserID → tanlangan qismlar (standart: faqat kesh)
    @Published var selection: [String: Set<BrowserPart>] = [:]

    func isOn(_ b: String, _ p: BrowserPart) -> Bool { selection[b, default: [.cache]].contains(p) }

    func set(_ b: String, _ p: BrowserPart, _ on: Bool) {
        var s = selection[b, default: [.cache]]
        if on { s.insert(p) } else { s.remove(p) }
        selection[b] = s
    }

    var selectedSize: Int64 {
        browsers.filter { !running.contains($0.id) }.reduce(0) { acc, b in
            acc + BrowserPart.allCases.filter { isOn(b.id, $0) }.reduce(0) { $0 + b.size($1) }
        }
    }

    /// Faqat yopiq brauzerlarning keshi (Aqlli skanerlash uchun)
    var safeCacheSize: Int64 {
        browsers.filter { !running.contains($0.id) }.reduce(0) { $0 + $1.size(.cache) }
    }

    var selectsSensitive: Bool {
        browsers.contains { b in isOn(b.id, .history) || isOn(b.id, .cookies) }
    }

    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard !scanning else { return nil }
        scanning = true
        message = nil
        return Task {
            let r = await Task.detached(priority: .userInitiated) { BrowserScanner.scanAll() }.value
            self.browsers = r
            self.refreshRunning()
            self.scanning = false
            self.scanned = true
        }
    }

    func refreshRunning() {
        running = Set(BrowserDef.all.filter(BrowserScanner.isRunning).map(\.id))
    }

    func quit(_ b: BrowserScan) {
        b.def.allBundleIDs.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.forEach { $0.terminate() }
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if !BrowserScanner.isRunning(b.def) { break }
            }
            self.refreshRunning()
        }
    }

    /// Tanlanganlarni tozalaydi. onlyCache — Aqlli skanerlash rejimi.
    @discardableResult
    func clean(onlyCache: Bool = false) -> Task<Int64, Never> {
        refreshRunning()
        var entries: [FileEntry] = []
        for b in browsers where !running.contains(b.id) {
            for p in BrowserPart.allCases where onlyCache ? p == .cache : isOn(b.id, p) {
                entries += b.parts[p] ?? []
            }
        }
        let skipped = browsers.filter { running.contains($0.id) }.map(\.def.name)
        let toRemove = entries
        return Task {
            let r = await Task.detached(priority: .userInitiated) { Remover.remove(toRemove, permanently: true) }.value
            var text = T("Brauzerlar: \(Format.bytes(r.freed)) tozalandi.", "Browsers: \(Format.bytes(r.freed)) cleaned.",
                         "Браузеры: очищено \(Format.bytes(r.freed)).")
            if !skipped.isEmpty {
                text += T(" Ochiq bo'lgani uchun o'tkazildi: \(skipped.joined(separator: ", ")).",
                          " Skipped (running): \(skipped.joined(separator: ", ")).",
                          " Пропущены (открыты): \(skipped.joined(separator: ", ")).")
            }
            self.message = text
            self.scan()
            return r.freed
        }
    }
}

struct BrowsersView: View {
    @EnvironmentObject var model: BrowsersModel
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "globe",
                       title: T("Brauzerlar", "Browsers", "Браузеры"),
                       subtitle: T("Kesh, tarix va cookie'lar — Safari, Chrome, Edge, Brave, Opera, Arc, Yandex, Firefox",
                                   "Cache, history and cookies — Safari, Chrome, Edge, Brave, Opera, Arc, Yandex, Firefox",
                                   "Кэш, история и cookies — Safari, Chrome, Edge, Brave, Opera, Arc, Яндекс, Firefox")) {
                Button(model.scanning ? T("Skanerlanmoqda…", "Scanning…", "Сканирование…") : T("Qayta skanerlash", "Rescan", "Пересканировать")) {
                    model.scan()
                }
                .buttonStyle(GhostButtonStyle()).disabled(model.scanning)
            }
            if let m = model.message { Label(m, systemImage: "checkmark.seal.fill").foregroundColor(Theme.green) }
            if !Permissions.hasFullDiskAccess {
                Label(T("Safari uchun Full Disk Access kerak", "Safari needs Full Disk Access", "Для Safari нужен полный доступ к диску"),
                      systemImage: "lock.shield").font(.caption).foregroundColor(Theme.orange)
            }

            if model.scanning && model.browsers.isEmpty {
                ProgressView(T("Brauzerlar tekshirilmoqda…", "Checking browsers…", "Проверка браузеров…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.browsers.isEmpty {
                EmptyState(icon: "globe", text: model.scanned
                           ? T("Tozalanadigan narsa yo'q", "Nothing to clean", "Нечего чистить")
                           : T("«Qayta skanerlash»ni bosing", "Press Rescan", "Нажмите «Пересканировать»"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(model.browsers.enumerated()), id: \.element.id) { i, b in
                            browserCard(b).fadeIn(Double(min(i, 8)) * 0.04)
                        }
                    }
                }
                BottomBar {
                    VStack(alignment: .leading) {
                        Text(T("Tanlangan: \(Format.bytes(model.selectedSize))", "Selected: \(Format.bytes(model.selectedSize))",
                               "Выбрано: \(Format.bytes(model.selectedSize))")).font(.headline)
                        Text(T("Ochiq brauzerlarga tegilmaydi", "Running browsers are skipped", "Открытые браузеры пропускаются"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(T("Tozalash", "Clean", "Очистить")) {
                        if model.selectsSensitive { confirm = true } else { model.clean() }
                    }
                    .buttonStyle(GlowButtonStyle()).disabled(model.selectedSize == 0)
                }
                .confirmationDialog(T("Tarix/cookie'lar ham o'chirilsinmi?", "Also delete history/cookies?", "Удалить также историю/cookies?"),
                                    isPresented: $confirm) {
                    Button(T("Tozalash", "Clean", "Очистить"), role: .destructive) { model.clean() }
                } message: {
                    Text(T("Cookie'lar o'chsa saytlardan chiqib ketasiz. Qaytarib bo'lmaydi.",
                           "Deleting cookies signs you out of websites. This can't be undone.",
                           "Удаление cookies выведет вас из аккаунтов. Отменить нельзя."))
                }
            }
        }
        .padding(24)
        .onAppear {
            if model.browsers.isEmpty { model.scan() } else { model.refreshRunning() }
        }
    }

    @ViewBuilder
    func browserCard(_ b: BrowserScan) -> some View {
        let isRunning = model.running.contains(b.id)
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.def.bundleID) {
                        Image(nsImage: IconCache.icon(url.path)).resizable().frame(width: 34, height: 34)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.def.name).font(.headline)
                        if isRunning {
                            Label(T("Ochiq — tozalash uchun yoping", "Running — quit to clean", "Открыт — закройте для очистки"),
                                  systemImage: "exclamationmark.circle").font(.caption).foregroundColor(Theme.orange)
                        }
                    }
                    Spacer()
                    Text(Format.bytes(b.total)).font(.system(.title3, design: .rounded).weight(.semibold))
                    if isRunning {
                        Button(T("Yopish", "Quit", "Закрыть")) { model.quit(b) }.buttonStyle(GhostButtonStyle())
                    }
                }
                HStack(spacing: 8) {
                    ForEach(BrowserPart.allCases, id: \.self) { p in
                        if b.size(p) > 0 {
                            Toggle(isOn: Binding(get: { model.isOn(b.id, p) }, set: { model.set(b.id, p, $0) })) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(p.title) · \(Format.bytes(b.size(p)))").font(.caption.weight(.semibold))
                                    Text(p.hint).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                        }
                    }
                }
                .disabled(isRunning)
                .opacity(isRunning ? 0.5 : 1)
            }
        }
    }
}
