import SwiftUI
import AppKit

// MARK: - Aqlli skanerlash: hamma modul bitta tugmada
//
// Skanerlash: keraksiz fayllar, eski dasturchi fayllari, Savat, snapshotlar, RAM,
// himoya, yangilanishlar va disk tahlili — parallel.
// Bajarish: tanlangan hamma narsa birdaniga; admin talab qiladiganlari bitta parol bilan.
// Natija: diskda HAQIQATAN qancha joy bo'shagani (oldin/keyin o'lchanadi).

@MainActor
final class SmartScanModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, results, running, done }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0
    @Published var step = ""

    // Natijalar
    @Published var trashEntries: [FileEntry] = []
    @Published var trashSize: Int64 = 0
    @Published var snapshots = 0
    @Published var purgeable: Int64 = 0
    @Published var threats = 0
    @Published var updates = 0
    @Published var unusedApps: [UnusedApp] = []

    // Nimalar bajariladi
    @Published var doJunk = true
    @Published var doBrowsers = true
    @Published var doDev = true
    @Published var doTrash = true
    @Published var doSnapshots = false   // snapshot — oxirgi "qutqaruv" nusxasi, shuning uchun o'zingiz yoqasiz
    @Published var doRAM = true

    // Yakun
    @Published var freedReal: Int64 = 0
    @Published var notes: [String] = []

    private var m: AppModels { AppModels.shared }

    var junkSize: Int64 { m.junk.selectedSize }
    /// Dasturchi fayllari — "Ko'rib chiqish"da siz belgilagan ro'yxatning o'zi
    var devItems: [FileEntry] { m.dev.items.filter(\.selected) }
    var devSize: Int64 { devItems.reduce(0) { $0 + $1.size } }

    /// Taxminan qancha bo'shaydi (snapshotlar kirmaydi — ular aniq o'lchanmaydi)
    var browserSize: Int64 { m.browsers.safeCacheSize }

    var estimate: Int64 {
        (doJunk ? junkSize : 0) + (doBrowsers ? browserSize : 0) + (doDev ? devSize : 0) + (doTrash ? trashSize : 0)
    }

    var canRun: Bool {
        (doJunk && junkSize > 0) || (doBrowsers && browserSize > 0) || (doDev && devSize > 0) || (doTrash && trashSize > 0)
            || (doSnapshots && snapshots > 0) || doRAM
    }

    private var doneSteps = 0.0
    private let totalSteps = 7.0

    private func tick(_ s: String) {
        doneSteps += 1
        withAnimation { progress = doneSteps / totalSteps }
        step = s
    }

    /// Boshqa ekrandan boshlangan ish tugashini kutish (eskirgan natija bo'lmasin)
    private func settle(_ busy: () -> Bool) async {
        while busy() { try? await Task.sleep(nanoseconds: 250_000_000) }
    }

    func scan() {
        guard phase != .scanning, phase != .running else { return }
        withAnimation(.spring()) { phase = .scanning }
        progress = 0
        notes = []
        Task {
            doneSteps = 0

            // Tarmoq va og'ir disk tahlili parallel boshlanadi
            await settle { m.updates.checking || m.disk.analyzing }
            let upd = m.updates.check()
            let diskTask = m.disk.analyze()

            step = T("Keraksiz fayllar…", "System junk…", "Системный мусор…")
            await settle { m.junk.scanning || m.junk.cleaning }
            await m.junk.scan()?.value
            await settle { m.junk.scanning }
            // Savatni faqat "Savat" kartasi boshqaradi
            let trashPrefixes = TrashInfo.locations().map { $0.path + "/" }
            for c in m.junk.categories.indices {
                for i in m.junk.categories[c].items.indices
                    where trashPrefixes.contains(where: { m.junk.categories[c].items[i].url.path.hasPrefix($0) }) {
                    m.junk.categories[c].items[i].selected = false
                }
            }
            tick(T("Brauzerlar…", "Browsers…", "Браузеры…"))
            await settle { m.browsers.scanning }
            await m.browsers.scan()?.value
            tick(T("Dasturchi fayllari…", "Developer junk…", "Мусор разработчика…"))

            async let dev = Task.detached(priority: .userInitiated) { DevScanner.scan(root: FS.home) }.value
            async let trash = Task.detached(priority: .utility) { () -> [FileEntry] in
                // Faqat ichki disk savati (T9 kabi tashqi disklar — Tizim keraksizlari'da, o'zingiz tanlaysiz)
                let t = FS.home.appendingPathComponent(".Trash")
                return FS.children(t).filter { $0.lastPathComponent != ".DS_Store" }
                    .map { FileEntry(url: $0, size: FS.allocatedSize(of: $0), modified: nil, selected: true) }
            }.value
            async let snaps = Task.detached(priority: .utility) { DiskAnalyzer.snapshotCount() }.value

            let devAll = await dev
            m.dev.items = devAll.map { e in
                var e = e
                // Bir tugmali rejimda: Python venv (qo'lda o'rnatilgan paketlar bo'lishi mumkin) — tanlanmaydi
                if (e.note ?? "").hasPrefix("Python venv") { e.selected = false }
                return e
            }
            m.dev.scanned = true
            tick(T("Savat…", "Trash…", "Корзина…"))
            trashEntries = Permissions.hasFullDiskAccess ? await trash : []
            trashSize = trashEntries.reduce(0) { $0 + $1.size }
            tick(T("Snapshotlar…", "Snapshots…", "Снимки…"))
            snapshots = await snaps
            purgeable = SystemStats.diskDetailed().purgeable
            tick(T("Himoya…", "Protection…", "Защита…"))

            await settle { m.protection.scanning }
            await m.protection.scan()?.value
            threats = m.protection.dangerCount
            tick(T("Yangilanishlar va disk tahlili…", "Updates and disk analysis…", "Обновления и анализ диска…"))

            await upd?.value
            await settle { m.updates.checking }
            updates = m.updates.updates.count
            await diskTask?.value
            await settle { m.disk.analyzing }
            unusedApps = m.disk.report?.unusedApps ?? []
            tick("")

            doRAM = m.memory.mem.fraction > 0.75
            doSnapshots = false
            withAnimation(.spring()) { phase = .results }
        }
    }

    func run() {
        guard phase == .results else { return }
        withAnimation(.spring()) { phase = .running }
        notes = []
        Task {
            let before = SystemStats.diskDetailed().free

            // 1) Savat — faqat skanerlashda ko'rsatilgan narsalar (keyin tushganlariga tegmaymiz)
            if doTrash, !trashEntries.isEmpty {
                step = T("Savat bo'shatilmoqda…", "Emptying Trash…", "Очистка Корзины…")
                let entries = trashEntries
                let r = await Task.detached { Remover.remove(entries, permanently: true) }.value
                notes.append(T("Savat: \(Format.bytes(r.freed))", "Trash: \(Format.bytes(r.freed))", "Корзина: \(Format.bytes(r.freed))"))
                trashEntries = []
            }
            // 2) Keraksiz fayllar (qaytarib olinadiganlari Savatga ketadi va u yerda qoladi)
            if doJunk, junkSize > 0 {
                step = T("Keraksiz fayllar tozalanmoqda…", "Cleaning system junk…", "Очистка мусора…")
                await settle { m.junk.scanning || m.junk.cleaning }
                await m.junk.clean(rescan: false)?.value
                if let msg = m.junk.message { notes.append(msg) }
            }
            // 2b) Brauzer keshi (faqat kesh, faqat yopiq brauzerlar)
            if doBrowsers, !m.browsers.browsers.isEmpty {
                step = T("Brauzer keshi tozalanmoqda…", "Cleaning browser caches…", "Очистка кэша браузеров…")
                _ = await m.browsers.clean(onlyCache: true).value
                if let msg = m.browsers.message { notes.append(msg) }
            }
            // 3) Eski loyiha fayllari — siz ko'rib chiqqan ro'yxat
            let dev = devItems
            if doDev, !dev.isEmpty {
                step = T("Dasturchi fayllari…", "Developer junk…", "Мусор разработчика…")
                let r = await Task.detached { Remover.remove(dev, permanently: true) }.value
                notes.append(T("Eski loyiha fayllari: \(Format.bytes(r.freed))", "Old project junk: \(Format.bytes(r.freed))",
                               "Старые файлы проектов: \(Format.bytes(r.freed))"))
                let removed = Set(dev.map(\.url)).subtracting(r.failed)
                m.dev.items.removeAll { removed.contains($0.url) }
            }
            // 4) Admin talab qiladiganlar — bitta parol
            var admin: [String] = []
            if doSnapshots, snapshots > 0 { admin.append("tmutil deletelocalsnapshots / ; tmutil thinlocalsnapshots / 999999999999 4") }
            if doRAM { admin.append("/usr/sbin/purge") }
            if !admin.isEmpty {
                step = T("Parol so'ralmoqda…", "Asking for your password…", "Запрос пароля…")
                try? await Task.sleep(nanoseconds: 150_000_000) // matn ekranda ko'rinsin
                let r = Admin.run(admin.joined(separator: " ; ") + " ; true")
                if r.ok {
                    if doSnapshots, snapshots > 0 {
                        let left = await Task.detached { DiskAnalyzer.snapshotCount() }.value
                        notes.append(left == 0
                            ? T("Time Machine snapshotlari o'chirildi", "Time Machine snapshots deleted", "Снимки Time Machine удалены")
                            : T("\(left) ta snapshot qoldi (macOS ruxsat bermadi)", "\(left) snapshots remain (macOS refused)",
                                "Осталось снимков: \(left) (macOS не разрешила)"))
                    }
                    if doRAM { notes.append(T("RAM bo'shatildi", "RAM freed", "RAM освобождена")) }
                } else {
                    notes.append(T("Parol kiritilmadi — snapshot/RAM o'tkazib yuborildi", "No password — snapshots/RAM skipped",
                                   "Пароль не введён — снимки/RAM пропущены"))
                }
            }

            // 5) Haqiqiy natija: APFS joyni biroz kechikib qaytaradi — 10 s gacha kutamiz
            step = T("Natija o'lchanmoqda…", "Measuring the result…", "Измеряем результат…")
            var after = SystemStats.diskDetailed().free
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let n = SystemStats.diskDetailed().free
                if n <= after { break }
                after = n
            }
            freedReal = max(after - before, 0)
            step = ""
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { phase = .done }
            m.junk.scan()
            m.smart.analyze(memory: m.memory, force: true)
        }
    }

    func reset() { withAnimation(.spring()) { phase = .idle } }
}

// MARK: - Natijalar ekrani

struct SmartModuleCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let color: Color
    var isOn: Binding<Bool>? = nil
    var review: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.2)).frame(width: 34, height: 34)
                    Image(systemName: icon).foregroundColor(color)
                }
                Spacer()
                if let isOn {
                    Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
            }
            Text(title).font(.subheadline.weight(.semibold))
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).numericTransition()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            if let review {
                Button(T("Ko'rib chiqish", "Review", "Подробнее"), action: review)
                    .buttonStyle(.borderless).font(.caption.weight(.semibold)).foregroundColor(Theme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hover ? Theme.cardHover : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke((isOn?.wrappedValue ?? false) ? color.opacity(0.6) : Theme.stroke, lineWidth: 1))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct SmartScanResults: View {
    @EnvironmentObject var scan: SmartScanModel
    @EnvironmentObject var browsers: BrowsersModel
    @EnvironmentObject var dev: DevModel
    @EnvironmentObject var junk: JunkModel
    @EnvironmentObject var memory: MemoryModel
    let go: (Panel) -> Void

    var body: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        VStack(spacing: 14) {
            LazyVGrid(columns: cols, spacing: 12) {
                SmartModuleCard(icon: "trash.circle", title: T("Keraksiz fayllar", "System junk", "Мусор"),
                                value: Format.bytes(scan.junkSize),
                                detail: T("Kesh, log, Claude/Electron, Xcode…", "Caches, logs, Claude/Electron, Xcode…", "Кэш, логи, Claude/Electron, Xcode…"),
                                color: Theme.accent, isOn: $scan.doJunk, review: { go(.junk) }).fadeIn(0)
                SmartModuleCard(icon: "globe", title: T("Brauzer keshi", "Browser cache", "Кэш браузеров"),
                                value: Format.bytes(scan.browserSize),
                                detail: T("Safari, Chrome, Edge… (ochiqlari o'tkaziladi)", "Safari, Chrome, Edge… (running ones skipped)",
                                          "Safari, Chrome, Edge… (открытые пропускаются)"),
                                color: Color(red: 0.2, green: 0.75, blue: 0.95), isOn: $scan.doBrowsers, review: { go(.browsers) }).fadeIn(0.02)
                SmartModuleCard(icon: "chevron.left.forwardslash.chevron.right", title: T("Eski loyiha fayllari", "Old project junk", "Старые файлы проектов"),
                                value: Format.bytes(scan.devSize),
                                detail: T("\(scan.devItems.count) ta — 30+ kun tegilmagan node_modules, venv…",
                                          "\(scan.devItems.count) items — node_modules, venv… untouched for 30+ days",
                                          "\(scan.devItems.count) шт. — node_modules, venv… не трогали 30+ дней"),
                                color: Color(red: 0.36, green: 0.62, blue: 1.0), isOn: $scan.doDev, review: { go(.dev) }).fadeIn(0.04)
                SmartModuleCard(icon: "trash", title: T("Savat", "Trash", "Корзина"),
                                value: Permissions.hasFullDiskAccess ? Format.bytes(scan.trashSize) : "—",
                                detail: Permissions.hasFullDiskAccess
                                    ? T("Bo'shatilmaguncha joy egallaydi", "Takes space until emptied", "Занимает место, пока не очищена")
                                    : T("Full Disk Access kerak", "Needs Full Disk Access", "Нужен полный доступ"),
                                color: Theme.orange, isOn: $scan.doTrash).fadeIn(0.08)
                SmartModuleCard(icon: "clock.arrow.circlepath", title: T("Time Machine snapshotlari", "Time Machine snapshots", "Снимки Time Machine"),
                                value: "\(scan.snapshots)",
                                detail: T("O'chirilgan fayllarni ushlab turadi (\(Format.bytes(scan.purgeable)) gacha). Oxirgi zaxira — o'zingiz yoqing.",
                                          "Hold deleted files (up to \(Format.bytes(scan.purgeable))). Your last safety net — opt in.",
                                          "Держат удалённые файлы (до \(Format.bytes(scan.purgeable))). Последняя страховка — включите сами."),
                                color: Theme.red, isOn: $scan.doSnapshots).fadeIn(0.12)
                SmartModuleCard(icon: "memorychip", title: T("Tezlik (RAM)", "Speed (RAM)", "Скорость (RAM)"),
                                value: "\(Int(memory.mem.fraction * 100))%",
                                detail: T("Faol bo'lmagan xotirani bo'shatish", "Free inactive memory", "Освободить неактивную память"),
                                color: Theme.green, isOn: $scan.doRAM, review: { go(.memory) }).fadeIn(0.16)
                SmartModuleCard(icon: "checkmark.shield", title: T("Himoya", "Protection", "Защита"),
                                value: scan.threats == 0 ? T("Toza", "Clean", "Чисто") : "\(scan.threats)",
                                detail: scan.threats == 0
                                    ? T("Xavfli narsa topilmadi", "No threats found", "Угроз нет")
                                    : T("Ko'rib chiqib olib tashlang", "Review and remove", "Проверьте и удалите"),
                                color: scan.threats == 0 ? Theme.green : Theme.red, review: { go(.protection) }).fadeIn(0.2)
                SmartModuleCard(icon: "arrow.down.app", title: T("Yangilanishlar", "Updates", "Обновления"),
                                value: "\(scan.updates)",
                                detail: T("Ilovalarning yangi versiyalari", "Newer app versions", "Новые версии приложений"),
                                color: Theme.accent2, review: { go(.updates) }).fadeIn(0.24)
                SmartModuleCard(icon: "moon.zzz", title: T("Ishlatilmayotgan ilovalar", "Unused apps", "Неиспользуемые"),
                                value: Format.bytes(scan.unusedApps.reduce(0) { $0 + $1.size }),
                                detail: T("\(scan.unusedApps.count) ta ilova 3 oydan beri ochilmagan",
                                          "\(scan.unusedApps.count) apps not opened for 3+ months",
                                          "\(scan.unusedApps.count) приложений не открывались 3+ месяца"),
                                color: Color.gray, review: { go(.uninstaller) }).fadeIn(0.28)
                SmartModuleCard(icon: "chart.bar.doc.horizontal", title: T("Disk tahlili", "Disk analysis", "Анализ диска"),
                                value: Format.bytes(AppModels.shared.disk.report?.used ?? 0),
                                detail: T("Joy qayerga ketganini ko'ring", "See where your space went", "Куда ушло место"),
                                color: Theme.accent, review: { go(.analyzer) }).fadeIn(0.32)
            }
        }
    }
}
