import SwiftUI
import AppKit

// MARK: - Ilova yangilanishlari
//
// Ko'p Mac ilovalari Sparkle orqali yangilanadi: Info.plist'da SUFeedURL (appcast XML) bo'ladi.
// Biz shu appcast'ni o'qib, eng yangi versiyani o'rnatilgani bilan solishtiramiz.
// App Store ilovalari App Store'ning o'zida yangilanadi — ular uchun alohida tugma bor.

struct AppUpdate: Identifiable, Sendable {
    var id: String { app.id }
    let app: AppInfo
    let current: String
    let latest: String
    let download: URL?
}

/// Appcast XML parser: har bir <item> uchun build, qisqa versiya, yuklash havolasi, kanal va minimal macOS.
/// <sparkle:deltas> ichidagi delta-enclosure'lar e'tiborga olinmaydi.
final class AppcastParser: NSObject, XMLParserDelegate {
    struct Item { var build: String?; var short: String?; var url: URL?; var channel: String?; var minOS: String? }
    private(set) var items: [Item] = []
    private var cur: Item?
    private var deltaDepth = 0
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let d = AppcastParser()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" { cur = Item() }
        if name == "sparkle:deltas" { deltaDepth += 1 }
        if name == "enclosure", deltaDepth == 0, cur != nil {
            if let v = attributes["sparkle:version"] { cur?.build = v }
            if let s = attributes["sparkle:shortVersionString"] { cur?.short = s }
            if let u = attributes["url"] { cur?.url = URL(string: u) }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "sparkle:deltas": deltaDepth -= 1
        case "sparkle:version" where deltaDepth == 0 && !t.isEmpty: cur?.build = t
        case "sparkle:shortVersionString" where deltaDepth == 0 && !t.isEmpty: cur?.short = t
        case "sparkle:channel": cur?.channel = t
        case "sparkle:minimumSystemVersion": cur?.minOS = t
        case "item":
            if let c = cur { items.append(c) }
            cur = nil
        default: break
        }
        text = ""
    }
}

enum VersionCompare {
    /// "2.10.1" > "2.9" kabi raqamli solishtirish.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

enum UpdateChecker {
    static func feedURL(_ app: URL) -> URL? {
        guard let s = Bundle(url: app)?.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return nil }
        return URL(string: s.trimmingCharacters(in: .whitespaces))
    }

    static func isAppStore(_ app: URL) -> Bool {
        FS.fm.fileExists(atPath: app.appendingPathComponent("Contents/_MASReceipt/receipt").path)
    }

    /// Sparkle qoidasi: sparkle:version (build) ↔ CFBundleVersion solishtiriladi; beta kanallar
    /// va bu macOS'ga mos kelmaydigan versiyalar o'tkazib yuboriladi.
    static func check(_ app: AppInfo, session: URLSession) async -> AppUpdate? {
        guard let feed = feedURL(app.url), feed.scheme == "https" || feed.scheme == "http" else { return nil }
        guard let (data, _) = try? await session.data(from: feed) else { return nil }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osStr = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let items = AppcastParser.parse(data).filter { item in
            (item.channel ?? "").isEmpty
                && (item.build ?? item.short) != nil
                && (item.minOS.map { !VersionCompare.isNewer($0, than: osStr) } ?? true)
        }
        func key(_ i: AppcastParser.Item) -> String { i.build ?? i.short ?? "" }
        guard let best = items.max(by: { VersionCompare.isNewer(key($1), than: key($0)) }) else { return nil }
        let curBuild = (Bundle(url: app.url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        let curShort = app.version
        let newer: Bool
        if let b = best.build, !curBuild.isEmpty {
            newer = VersionCompare.isNewer(b, than: curBuild)
        } else if let s = best.short ?? best.build, !curShort.isEmpty {
            newer = VersionCompare.isNewer(s, than: curShort)
        } else {
            return nil
        }
        guard newer else { return nil }
        return AppUpdate(app: app, current: curShort.isEmpty ? curBuild : curShort,
                         latest: best.short ?? best.build ?? "", download: best.url)
    }
}

@MainActor
final class UpdatesModel: ObservableObject {
    @Published var updates: [AppUpdate] = []
    @Published var checking = false
    @Published var checked = false
    @Published var checkedCount = 0
    @Published var appStoreCount = 0
    @Published var progress: Double = 0

    func check() {
        guard !checking else { return }
        checking = true
        progress = 0
        Task {
            // Info.plist o'qish asosiy oqimdan tashqarida
            let (sparkle, storeCount) = await Task.detached { () -> ([AppInfo], Int) in
                let apps = AppScanner.installedApps()
                let store = apps.filter { UpdateChecker.isAppStore($0.url) }
                let sp = apps.filter { !UpdateChecker.isAppStore($0.url) && UpdateChecker.feedURL($0.url) != nil }
                return (sp, store.count)
            }.value
            self.appStoreCount = storeCount
            self.checkedCount = sparkle.count
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 10
            cfg.timeoutIntervalForResource = 20
            let session = URLSession(configuration: cfg)
            var found: [AppUpdate] = []
            var done = 0
            // Bir vaqtda ko'pi bilan 6 ta so'rov — tarmoq va CPU yengil qoladi
            await withTaskGroup(of: AppUpdate?.self) { group in
                var it = sparkle.makeIterator()
                for _ in 0..<6 { if let a = it.next() { group.addTask { await UpdateChecker.check(a, session: session) } } }
                for await r in group {
                    done += 1
                    self.progress = sparkle.isEmpty ? 1 : Double(done) / Double(sparkle.count)
                    if let r { found.append(r) }
                    if let a = it.next() { group.addTask { await UpdateChecker.check(a, session: session) } }
                }
            }
            self.updates = found.sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
            self.checking = false
            self.checked = true
            session.invalidateAndCancel()
        }
    }

    func openApp(_ u: AppUpdate) {
        NSWorkspace.shared.openApplication(at: u.app.url, configuration: NSWorkspace.OpenConfiguration())
    }

    func download(_ u: AppUpdate) {
        if let d = u.download { NSWorkspace.shared.open(d) } else { openApp(u) }
    }

    func openAppStoreUpdates() {
        if let u = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(u) }
    }
}

struct UpdatesView: View {
    @EnvironmentObject var model: UpdatesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "arrow.down.app",
                       title: T("Yangilanishlar", "Updates", "Обновления"),
                       subtitle: T("O'rnatilgan ilovalarning yangi versiyalarini tekshiradi",
                                   "Checks installed apps for newer versions",
                                   "Проверяет новые версии установленных приложений")) {
                HStack {
                    if model.appStoreCount > 0 {
                        Button(T("App Store (\(model.appStoreCount))", "App Store (\(model.appStoreCount))", "App Store (\(model.appStoreCount))")) {
                            model.openAppStoreUpdates()
                        }.buttonStyle(GhostButtonStyle())
                    }
                    Button(model.checking ? T("Tekshirilmoqda…", "Checking…", "Проверка…") : T("Tekshirish", "Check", "Проверить")) {
                        model.check()
                    }
                    .buttonStyle(GlowButtonStyle()).disabled(model.checking)
                }
            }
            if model.checking {
                VStack(spacing: 14) {
                    Spacer()
                    ScanProgressRing(progress: model.progress)
                    Text(T("\(model.checkedCount) ta ilova tekshirilmoqda…", "Checking \(model.checkedCount) apps…",
                           "Проверка \(model.checkedCount) приложений…")).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else if !model.checked {
                EmptyState(icon: "arrow.down.app",
                           text: T("«Tekshirish»ni bosing. Internet kerak bo'ladi.", "Press Check. Requires internet.",
                                   "Нажмите «Проверить». Нужен интернет."))
            } else if model.updates.isEmpty {
                EmptyState(icon: "checkmark.seal",
                           text: T("Hamma ilovalar eng yangi versiyada (\(model.checkedCount) ta tekshirildi).",
                                   "All apps are up to date (\(model.checkedCount) checked).",
                                   "Все приложения обновлены (проверено \(model.checkedCount))."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(model.updates.enumerated()), id: \.element.id) { i, u in
                            Card(padding: 12) {
                                HStack(spacing: 12) {
                                    Image(nsImage: IconCache.icon(u.app.url.path)).resizable().frame(width: 40, height: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(u.app.name).font(.headline)
                                        HStack(spacing: 6) {
                                            Text(u.current).foregroundStyle(.secondary)
                                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                                            Text(u.latest).foregroundColor(Theme.green).fontWeight(.semibold)
                                        }
                                        .font(.caption)
                                    }
                                    Spacer()
                                    Button(T("Ilovani ochish", "Open app", "Открыть")) { model.openApp(u) }
                                        .buttonStyle(GhostButtonStyle())
                                        .help(T("Ko'p ilovalar ochilganda o'zi yangilanishni taklif qiladi",
                                                "Most apps offer to update themselves when opened",
                                                "Большинство приложений предлагают обновиться при запуске"))
                                    Button(T("Yuklab olish", "Download", "Скачать")) { model.download(u) }
                                        .buttonStyle(GlowButtonStyle())
                                }
                            }
                            .fadeIn(Double(min(i, 10)) * 0.03)
                        }
                    }
                }
                Text(T("Faqat Sparkle orqali yangilanadigan ilovalar tekshiriladi. App Store ilovalari — App Store'da.",
                       "Only apps that update via Sparkle are checked. App Store apps update in the App Store.",
                       "Проверяются приложения, обновляемые через Sparkle. Приложения App Store — в App Store."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}
