import SwiftUI
import AppKit

// MARK: - Disk tahlili: joy qayerga ketgan va u bilan nima qilish kerak
//
// Mac'ning o'zida ishlaydigan "ekspert" qoidalar: diskni toifalarga bo'lib o'lchaydi,
// eng katta papkalarni topadi va har biriga tushunarli maslahat beradi.

struct DiskSlice: Identifiable, Sendable {
    let id: String
    let name: String
    let size: Int64
    let colorIndex: Int
}

struct BigFolder: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let advice: String?
    let safe: Bool          // xavfsiz tozalash mumkinmi (masalan kesh)
    let panel: Panel?
}

struct UnusedApp: Identifiable, Sendable {
    var id: String { app.id }
    let app: AppInfo
    let size: Int64
    let lastUsed: Date?
}

struct DiskReport: Sendable {
    var total: Int64 = 0
    var free: Int64 = 0
    var purgeable: Int64 = 0
    var snapshots = 0
    var slices: [DiskSlice] = []
    var bigFolders: [BigFolder] = []
    var unusedApps: [UnusedApp] = []
    var used: Int64 { max(total - free, 0) }
}

enum DiskAnalyzer {
    /// Ma'lum katta papkalar bo'yicha maslahatlar (yo'l qismi → maslahat).
    static func knowledge(for path: String) -> (String, Bool, Panel?)? {
        let p = path.lowercased()
        let homeCaches: String = FS.home.path.lowercased() + "/library/caches"
        let rules: [(String, String, Bool, Panel?)] = [
            ("/application support/claude", T("Claude (VM). Tozalasangiz, Claude kerak bo'lganda qayta yuklaydi.",
                                               "Claude (VM). If cleaned, Claude re-downloads it when needed.",
                                               "Claude (VM). Если очистить, Claude скачает заново при необходимости."), false, .junk),
            ("wondershare filmora", T("Filmora render va proxy keshi. Filmora → Sozlamalar → Keshni tozalash.",
                                      "Filmora render/proxy cache. Filmora → Preferences → Clear cache.",
                                      "Кэш рендера Filmora. Filmora → Настройки → Очистить кэш."), false, nil),
            ("/application support/logic", T("Logic kutubxonasi. Logic Pro → Sound Library → Relocate bilan T9 ga ko'chiring.",
                         "Logic library. Use Logic Pro → Sound Library → Relocate to move it to an external disk.",
                         "Библиотека Logic. Logic Pro → Sound Library → Relocate — перенесите на внешний диск."), false, nil),
            ("garageband", T("GarageBand kutubxonasi. Ishlatmasangiz, GarageBand'ni o'chirish bilan ketadi.",
                             "GarageBand library. If you don't use it, remove GarageBand.",
                             "Библиотека GarageBand. Не пользуетесь — удалите GarageBand."), false, .uninstaller),
            ("native instruments", T("Native Instruments kutubxonalari. Native Access orqali tashqi diskka ko'chiring.",
                                     "Native Instruments libraries. Move them to an external disk via Native Access.",
                                     "Библиотеки Native Instruments. Перенесите через Native Access на внешний диск."), false, nil),
            ("spectrasonics", T("Spectrasonics (Omnisphere) kutubxonasi — tashqi diskka ko'chirsa bo'ladi.",
                                "Spectrasonics (Omnisphere) library — can be moved to an external disk.",
                                "Библиотека Spectrasonics — можно перенести на внешний диск."), false, nil),
            ("/developer/coresimulator", T("Xcode simulyatorlari — Dasturchi keraksizlari bo'limida tozalang.",
                                           "Xcode simulators — clean them in Developer Junk.",
                                           "Симуляторы Xcode — очистите в «Мусор разработчика»."), true, .dev),
            ("/developer/xcode", T("Xcode fayllari (DerivedData, qurilma fayllari) — xavfsiz tozalanadi.",
                                   "Xcode files (DerivedData, device support) — safe to clean.",
                                   "Файлы Xcode (DerivedData и др.) — можно очистить."), true, .junk),
            ("com.docker.docker", T("Docker obrazlari. Docker Desktop → Troubleshoot → Clean / Purge data.",
                                    "Docker images. Docker Desktop → Troubleshoot → Clean / Purge data.",
                                    "Образы Docker. Docker Desktop → Troubleshoot → Clean / Purge data."), false, nil),
            ("mobile documents", T("iCloud Drive fayllari. iCloud sozlamalarida «Optimize Mac Storage»ni yoqing.",
                                   "iCloud Drive files. Turn on \"Optimize Mac Storage\" in iCloud settings.",
                                   "Файлы iCloud Drive. Включите «Оптимизировать хранилище Mac»."), false, nil),
            ("/library/messages", T("Xabarlar biriktirmalari. Xabarlar → Sozlamalar → xabarlarni saqlash muddatini qisqartiring.",
                                    "Messages attachments. Messages → Settings → keep messages for a shorter time.",
                                    "Вложения «Сообщений». Сократите срок хранения сообщений."), false, nil),
            ("mobilesync/backup", T("iPhone zaxira nusxalari — eskilarini Tizim keraksizlari'da o'chiring.",
                                    "iPhone backups — delete old ones in System Junk.",
                                    "Бэкапы iPhone — удалите старые в «Системный мусор»."), true, .junk),
            ("/actions-runner", T("GitHub build-server — qoldiqlari Tizim keraksizlari'da tozalanadi.",
                                  "GitHub runner — its leftovers are cleaned in System Junk.",
                                  "GitHub runner — остатки очищаются в «Системный мусор»."), true, .junk),
            ("/.cache", T("Python/AI keshi — Tizim keraksizlari'da ko'rib chiqing.",
                          "Python/AI cache — review it in System Junk.",
                          "Кэш Python/AI — смотрите в «Системный мусор»."), false, .junk),
            ("/downloads", T("Yuklab olinganlar — eski va katta fayllarni Katta fayllar'da ko'rib chiqing.",
                             "Downloads — review old and large files in Large Files.",
                             "Загрузки — пересмотрите старые и большие файлы."), false, .large),
            ("/movies", T("Videolar — keraklilarini T9 kabi tashqi diskka ko'chiring.",
                          "Videos — move the ones you keep to an external disk.",
                          "Видео — перенесите нужные на внешний диск."), false, .large),
            ("/music", T("Musiqa va loyihalar — tugallanganlarini tashqi diskka ko'chiring.",
                         "Music and projects — move finished ones to an external disk.",
                         "Музыка и проекты — завершённые перенесите на внешний диск."), false, .large),
            ("/pictures", T("Rasmlar. Photos → Sozlamalar → iCloud → «Optimize Mac Storage».",
                            "Pictures. Photos → Settings → iCloud → \"Optimize Mac Storage\".",
                            "Фото. Фото → Настройки → iCloud → «Оптимизировать хранилище»."), false, nil),
            (homeCaches, T("Keshlar — xavfsiz tozalanadi.", "Caches — safe to clean.", "Кэши — можно очистить."), true, .junk),
            ("/.trash", T("Savat — bo'shatilmaguncha joy egallaydi.", "Trash — takes space until emptied.",
                          "Корзина — занимает место, пока не очищена."), true, .junk)
        ]
        for (needle, advice, safe, panel) in rules where p.contains(needle) { return (advice, safe, panel) }
        return nil
    }

    static func lastUsed(_ app: URL) -> Date? {
        let out = Shell.run("/usr/bin/mdls", ["-raw", "-name", "kMDItemLastUsedDate", app.path]).out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty, out != "(null)" else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f.date(from: out)
    }

    static func snapshotCount() -> Int {
        Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).out
            .split(separator: "\n").filter { $0.contains("com.apple") }.count
    }

    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var sizes: [String: Int64] = [:]
        func set(_ k: String, _ v: Int64) { lock.lock(); sizes[k] = v; lock.unlock() }
    }

    static func analyze(progress: (@Sendable (Double) -> Void)? = nil) -> DiskReport {
        var r = DiskReport()
        let root = URL(fileURLWithPath: "/")
        let v = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                   .volumeAvailableCapacityForImportantUsageKey])
        r.total = Int64(v?.volumeTotalCapacity ?? 0)
        r.free = Int64(v?.volumeAvailableCapacity ?? 0)
        let important = v?.volumeAvailableCapacityForImportantUsage ?? r.free
        r.purgeable = max(important - r.free, 0)
        r.snapshots = snapshotCount()

        // O'lchanadigan joylar: ilovalar, uy papkasi qismlari, Library ichi, umumiy kutubxonalar
        let home = FS.home
        var targets: [URL] = []
        let apps = FS.children(URL(fileURLWithPath: "/Applications")) + FS.children(home.appendingPathComponent("Applications"))
        targets += apps
        let homeKids = FS.children(home).filter { $0.lastPathComponent != "Library" && $0.lastPathComponent != "Applications" }
        targets += homeKids
        let lib = home.appendingPathComponent("Library")
        let libKids = FS.children(lib).filter { $0.lastPathComponent != "Application Support" }
        targets += libKids
        let appSupport = FS.children(lib.appendingPathComponent("Application Support"))
        targets += appSupport
        let sysLib = FS.children(URL(fileURLWithPath: "/Library")).filter { $0.lastPathComponent != "Application Support" }
        let sysAppSupport = FS.children(URL(fileURLWithPath: "/Library/Application Support"))
        targets += sysLib + sysAppSupport
        let shared = [URL(fileURLWithPath: "/Users/Shared")]
        targets += shared

        // I: Full Disk Access bo'lmasa, macOS ruxsat so'rab bezovta qiladigan papkalarga kirmaymiz
        if !Permissions.hasFullDiskAccess {
            let tcc = ["/Desktop", "/Documents", "/Downloads", "/Library/Containers", "/Library/Mail", "/Library/Messages",
                       "/Library/Safari", "/Library/Group Containers"].map { home.path + $0 }
            targets.removeAll { tcc.contains($0.path) }
        }
        let allTargets = targets
        let box = Box()
        let total = Double(allTargets.count)
        let doneBox = Box()
        DispatchQueue.concurrentPerform(iterations: allTargets.count) { i in
            let u = allTargets[i]
            box.set(u.path, FS.allocatedSize(of: u))
            doneBox.lock.lock(); let n = (doneBox.sizes["n"] ?? 0) + 1; doneBox.sizes["n"] = n; doneBox.lock.unlock()
            if n % 8 == 0 { progress?(Double(n) / max(total, 1)) }
        }
        let s = box.sizes
        func sum(_ list: [URL]) -> Int64 { list.reduce(0) { $0 + (s[$1.path] ?? 0) } }

        let appsSize = sum(apps)
        let userFiles = sum(homeKids)
        let appData = sum(libKids) + sum(appSupport)
        let libraries = sum(sysLib) + sum(sysAppSupport) + sum(shared)
        let measured = appsSize + userFiles + appData + libraries
        let system = max(r.used - measured - r.purgeable, 0)
        r.slices = [
            DiskSlice(id: "apps", name: T("Ilovalar", "Applications", "Приложения"), size: appsSize, colorIndex: 0),
            DiskSlice(id: "user", name: T("Sizning fayllaringiz", "Your files", "Ваши файлы"), size: userFiles, colorIndex: 1),
            DiskSlice(id: "appdata", name: T("Ilova ma'lumotlari", "App data", "Данные приложений"), size: appData, colorIndex: 2),
            DiskSlice(id: "libs", name: T("Kutubxonalar (samplelar, plaginlar)", "Libraries (samples, plug-ins)", "Библиотеки (сэмплы, плагины)"),
                      size: libraries, colorIndex: 3),
            DiskSlice(id: "purge", name: T("Snapshotlar / tozalanadigan", "Snapshots / purgeable", "Снимки / очищаемое"),
                      size: r.purgeable, colorIndex: 4),
            DiskSlice(id: "system", name: T("macOS va tizim", "macOS & system", "macOS и система"), size: system, colorIndex: 5)
        ]

        // Eng katta papkalar (ilovalardan tashqari) + maslahat
        let folderCandidates = homeKids + libKids + appSupport + sysLib + sysAppSupport + shared
        r.bigFolders = folderCandidates
            .compactMap { u -> BigFolder? in
                let size = s[u.path] ?? 0
                guard size > 1_000_000_000 else { return nil }
                let k = knowledge(for: u.path)
                return BigFolder(url: u, size: size, advice: k?.0, safe: k?.1 ?? false, panel: k?.2)
            }
            .sorted { $0.size > $1.size }
            .prefix(14).map { $0 }

        // Ishlatilmayotgan katta ilovalar (90+ kun ochilmagan, 500 MB+)
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        r.unusedApps = apps
            .filter { $0.pathExtension == "app" && (s[$0.path] ?? 0) > 500_000_000 }
            .compactMap { u -> UnusedApp? in
                let info = AppScanner.info(u)
                guard !info.bundleID.hasPrefix("com.apple."), info.bundleID != Bundle.main.bundleIdentifier else { return nil }
                // Sana yo'q bo'lsa (Spotlight o'chiq yoki plagin sifatida ishlatiladi) — ayblamaymiz
                guard let used = lastUsed(u), used < cutoff else { return nil }
                return UnusedApp(app: info, size: s[u.path] ?? 0, lastUsed: used)
            }
            .sorted { $0.size > $1.size }
        progress?(1)
        return r
    }
}

@MainActor
final class DiskAnalyzerModel: ObservableObject {
    @Published var report: DiskReport?
    @Published var analyzing = false
    @Published var progress: Double = 0
    @Published var message: String?

    @discardableResult
    func analyze() -> Task<Void, Never>? {
        guard !analyzing else { return nil }
        analyzing = true
        progress = 0
        return Task {
            let r = await Task.detached(priority: .userInitiated) {
                DiskAnalyzer.analyze { p in Task { @MainActor in self.progress = max(self.progress, p) } }
            }.value
            withAnimation(.spring()) { self.report = r }
            self.analyzing = false
        }
    }

    /// Time Machine lokal snapshotlarini o'chiradi (parol so'raladi).
    func deleteSnapshots() {
        let before = SystemStats.diskDetailed().free
        let r = Admin.run("tmutil deletelocalsnapshots / ; tmutil thinlocalsnapshots / 999999999999 4 ; true")
        guard r.ok else { message = r.out; return }
        Task {
            var after = SystemStats.diskDetailed().free
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let n = SystemStats.diskDetailed().free
                if n <= after { break }
                after = n
            }
            message = T("Snapshotlar o'chirildi. Bo'shagan joy: \(Format.bytes(max(after - before, 0)))",
                        "Snapshots deleted. Space freed: \(Format.bytes(max(after - before, 0)))",
                        "Снимки удалены. Освобождено: \(Format.bytes(max(after - before, 0)))")
            analyze()
        }
    }
}

// MARK: - View

struct DiskBar: View {
    let report: DiskReport
    static let colors: [Color] = [Theme.accent, Color(red: 0.36, green: 0.62, blue: 1.0), Theme.accent2,
                                  Theme.orange, Theme.red, Color.gray, Color.white.opacity(0.08)]

    var body: some View {
        let total = max(Double(report.total), 1)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(report.slices) { s in
                        if s.size > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DiskBar.colors[s.colorIndex])
                                .frame(width: max(3, g.size.width * Double(s.size) / total))
                                .help("\(s.name): \(Format.bytes(s.size))")
                        }
                    }
                    RoundedRectangle(cornerRadius: 4).fill(DiskBar.colors[6])
                }
            }
            .frame(height: 22)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(report.slices) { s in
                    HStack(spacing: 6) {
                        Circle().fill(DiskBar.colors[s.colorIndex]).frame(width: 9, height: 9)
                        Text(s.name).font(.caption)
                        Text(Format.bytes(s.size)).font(.caption.weight(.semibold))
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 9, height: 9)
                    Text(T("Bo'sh", "Free", "Свободно")).font(.caption)
                    Text(Format.bytes(report.free)).font(.caption.weight(.semibold))
                }
            }
        }
    }
}

struct DiskAnalyzerView: View {
    @EnvironmentObject var model: DiskAnalyzerModel
    let go: (Panel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "chart.bar.doc.horizontal",
                       title: T("Disk tahlili", "Disk Analyzer", "Анализ диска"),
                       subtitle: T("Joy qayerga ketganini va har biri bilan nima qilish kerakligini ko'rsatadi",
                                   "Shows where your space went and what to do about each part",
                                   "Показывает, куда ушло место и что с этим делать")) {
                Button(model.analyzing ? T("Tahlil qilinmoqda…", "Analyzing…", "Анализ…") : T("Tahlil qilish", "Analyze", "Анализировать")) {
                    model.analyze()
                }
                .buttonStyle(GlowButtonStyle()).disabled(model.analyzing)
            }
            if let m = model.message { Label(m, systemImage: "info.circle.fill").foregroundColor(Theme.green) }

            if model.analyzing && model.report == nil {
                VStack(spacing: 14) {
                    Spacer()
                    ScanProgressRing(progress: model.progress)
                    Text(T("Disk o'lchanmoqda…", "Measuring the disk…", "Измерение диска…")).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else if let r = model.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(T("\(Format.bytes(r.used)) band / \(Format.bytes(r.total))",
                                           "\(Format.bytes(r.used)) used of \(Format.bytes(r.total))",
                                           "Занято \(Format.bytes(r.used)) из \(Format.bytes(r.total))")).font(.title3.bold())
                                    Spacer()
                                    if model.analyzing { ProgressView().controlSize(.small) }
                                }
                                DiskBar(report: r)
                            }
                        }
                        .fadeIn(0)

                        if r.snapshots > 0 {
                            ActionRow(icon: "clock.arrow.circlepath", color: Theme.orange,
                                      title: T("\(r.snapshots) ta Time Machine snapshoti", "\(r.snapshots) Time Machine snapshots",
                                               "Снимков Time Machine: \(r.snapshots)"),
                                      detail: T("O'chirilgan fayllar ichida saqlanib, joyni ushlab turibdi (~\(Format.bytes(r.purgeable))).",
                                                "They keep deleted files around and hold space (~\(Format.bytes(r.purgeable))).",
                                                "Хранят удалённые файлы и держат место (~\(Format.bytes(r.purgeable)))."),
                                      button: T("O'chirish", "Delete", "Удалить")) { model.deleteSnapshots() }
                                .fadeIn(0.05)
                        }

                        if !r.unusedApps.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label(T("3 oydan beri ochilmagan ilovalar", "Apps unused for 3+ months", "Не открывались 3+ месяца"),
                                              systemImage: "moon.zzz").font(.headline)
                                        Spacer()
                                        Text(Format.bytes(r.unusedApps.reduce(0) { $0 + $1.size })).font(.headline)
                                        Button(T("Ko'rib chiqish", "Review", "Посмотреть")) { go(.uninstaller) }
                                            .buttonStyle(GhostButtonStyle())
                                    }
                                    ForEach(r.unusedApps.prefix(6)) { a in
                                        HStack {
                                            Image(nsImage: IconCache.icon(a.app.url.path)).resizable().frame(width: 22, height: 22)
                                            Text(a.app.name)
                                            Spacer()
                                            Text(a.lastUsed.map { Format.relative($0) } ?? T("hech qachon", "never", "никогда"))
                                                .font(.caption).foregroundStyle(.secondary)
                                            Text(Format.bytes(a.size)).font(.callout.weight(.medium)).frame(width: 80, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                            .fadeIn(0.1)
                        }

                        Text(T("Eng katta papkalar", "Largest folders", "Самые большие папки")).font(.headline).padding(.top, 4)
                        ForEach(Array(r.bigFolders.enumerated()), id: \.element.id) { i, f in
                            Card(padding: 12) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(nsImage: IconCache.icon(f.url.path)).resizable().frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(f.url.lastPathComponent).font(.subheadline.weight(.semibold))
                                            if f.safe {
                                                Text(T("tozalasa bo'ladi", "safe to clean", "можно чистить")).font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(Capsule().fill(Theme.green.opacity(0.18))).foregroundColor(Theme.green)
                                            }
                                        }
                                        Text(shortPath(f.url.deletingLastPathComponent())).font(.caption2).foregroundStyle(.secondary)
                                        if let a = f.advice {
                                            Label(a, systemImage: "lightbulb").font(.caption).foregroundColor(Theme.accent)
                                        }
                                    }
                                    Spacer()
                                    Text(Format.bytes(f.size)).font(.callout.weight(.semibold))
                                    if let p = f.panel {
                                        Button(T("Hal qilish", "Fix", "Исправить")) { go(p) }.buttonStyle(GhostButtonStyle())
                                    }
                                    Button { FS.reveal(f.url) } label: { Image(systemName: "magnifyingglass") }
                                        .buttonStyle(.borderless)
                                }
                            }
                            .fadeIn(0.15 + Double(min(i, 10)) * 0.03)
                        }
                    }
                }
            } else {
                EmptyState(icon: "chart.bar.doc.horizontal",
                           text: T("«Tahlil qilish»ni bosing — 1–2 daqiqa", "Press Analyze — takes 1–2 minutes",
                                   "Нажмите «Анализировать» — 1–2 минуты"))
            }
        }
        .padding(24)
        .onAppear { if model.report == nil { model.analyze() } }
    }
}

/// Belgi + matn + tugma qatori (maslahatlar uchun).
struct ActionRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let button: String
    let action: () -> Void

    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 36, height: 36)
                    Image(systemName: icon).foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(button, action: action).buttonStyle(GlowButtonStyle())
            }
        }
    }
}
