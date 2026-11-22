import SwiftUI
import AppKit
import UserNotifications

/// Aqlli yordamchi: Mac holatini tahlil qilib, eng foydali harakatlarni taklif qiladi.
struct SmartTip: Identifiable, Sendable {
    enum Level: Int, Sendable { case info = 0, warn = 1, critical = 2 }
    let id: String
    let icon: String
    let title: String
    let detail: String
    let level: Level
    let panel: Panel?
    var size: Int64 = 0
}

enum SmartAnalyzer {
    static func dirSize(_ p: String) -> Int64 {
        let u = FS.expand(p)
        return FS.exists(u) ? FS.allocatedSize(of: u) : 0
    }

    static func localSnapshots() -> Int {
        let out = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).out
        return out.split(separator: "\n").filter { $0.contains("com.apple") }.count
    }

    static func thirdPartyAgents() -> Int {
        ["~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
            .flatMap { FS.children(FS.expand($0)) }
            .filter { $0.pathExtension == "plist" && !$0.lastPathComponent.hasPrefix("com.apple.") }
            .count
    }

    /// Og'ir emas: faqat aniq joylarni o'lchaydi (bir necha soniya).
    static func analyze(diskTotal: Int64, diskFree: Int64, mem: MemStats) -> [SmartTip] {
        var tips: [SmartTip] = []
        let freeRatio = diskTotal > 0 ? Double(diskFree) / Double(diskTotal) : 1

        if freeRatio < 0.10 || diskFree < 15_000_000_000 {
            tips.append(SmartTip(id: "disk", icon: "externaldrive.badge.exclamationmark",
                                 title: T("Disk deyarli to'la", "Disk is almost full", "Диск почти заполнен"),
                                 detail: T("Atigi \(Format.bytes(diskFree)) bo'sh. macOS sekinlashadi — tozalashni boshlang.",
                                           "Only \(Format.bytes(diskFree)) free. macOS slows down — start a cleanup.",
                                           "Свободно всего \(Format.bytes(diskFree)). macOS замедляется — начните очистку."),
                                 level: .critical, panel: .junk))
        }

        let claude = ["~/Library/Application Support/Claude/vm_bundles",
                      "~/Library/Application Support/Claude/Cache",
                      "~/Library/Application Support/Claude/Code Cache",
                      "~/Library/Caches/com.anthropic.claudefordesktop"].reduce(Int64(0)) { $0 + dirSize($1) }
        if claude > 1_000_000_000 {
            tips.append(SmartTip(id: "claude", icon: "brain",
                                 title: T("Claude keshi katta", "Claude cache is large", "Большой кэш Claude"),
                                 detail: T("Claude Desktop \(Format.bytes(claude)) egallagan. Kerak bo'lsa qayta yuklanadi.",
                                           "Claude Desktop uses \(Format.bytes(claude)). It's re-downloaded when needed.",
                                           "Claude Desktop занимает \(Format.bytes(claude)). Скачается заново при необходимости."),
                                 level: .warn, panel: .junk, size: claude))
        }

        let caches = dirSize("~/Library/Caches")
        if caches > 2_000_000_000 {
            tips.append(SmartTip(id: "caches", icon: "archivebox",
                                 title: T("Keshlar to'planib qolgan", "Caches have piled up", "Накопился кэш"),
                                 detail: T("\(Format.bytes(caches)) kesh — xavfsiz tozalanadi.",
                                           "\(Format.bytes(caches)) of caches — safe to clean.",
                                           "\(Format.bytes(caches)) кэша — можно безопасно удалить."),
                                 level: .warn, panel: .junk, size: caches))
        }

        let derived = dirSize("~/Library/Developer/Xcode/DerivedData")
        if derived > 2_000_000_000 {
            tips.append(SmartTip(id: "xcode", icon: "hammer",
                                 title: "Xcode DerivedData",
                                 detail: T("\(Format.bytes(derived)) — loyihalar qayta yig'ilganda tiklanadi.",
                                           "\(Format.bytes(derived)) — rebuilt automatically on next build.",
                                           "\(Format.bytes(derived)) — восстановится при следующей сборке."),
                                 level: .info, panel: .junk, size: derived))
        }

        let trash = dirSize("~/.Trash")
        if trash > 500_000_000 {
            tips.append(SmartTip(id: "trash", icon: "trash",
                                 title: T("Savat to'la", "Trash is full", "Корзина переполнена"),
                                 detail: T("Savatda \(Format.bytes(trash)) yotibdi.",
                                           "\(Format.bytes(trash)) is sitting in the Trash.",
                                           "В Корзине лежит \(Format.bytes(trash))."),
                                 level: .info, panel: .junk, size: trash))
        }

        let installers = FS.children(FS.expand("~/Downloads"))
            .filter { ["dmg", "pkg", "xip"].contains($0.pathExtension.lowercased()) }
            .reduce(Int64(0)) { $0 + FS.allocatedSize(of: $1) }
        if installers > 300_000_000 {
            tips.append(SmartTip(id: "installers", icon: "shippingbox",
                                 title: T("Eski o'rnatuvchilar", "Leftover installers", "Старые установщики"),
                                 detail: T("Downloads'da \(Format.bytes(installers)) .dmg/.pkg — ilovalar allaqachon o'rnatilgan bo'lsa, keraksiz.",
                                           "\(Format.bytes(installers)) of .dmg/.pkg in Downloads — not needed once apps are installed.",
                                           "\(Format.bytes(installers)) .dmg/.pkg в Загрузках — не нужны после установки."),
                                 level: .info, panel: .junk, size: installers))
        }

        let snaps = localSnapshots()
        if snaps > 0 {
            tips.append(SmartTip(id: "snap", icon: "clock.arrow.circlepath",
                                 title: T("Time Machine snapshotlari", "Time Machine snapshots", "Снимки Time Machine"),
                                 detail: T("\(snaps) ta lokal snapshot «purgeable» joyni band qilmoqda.",
                                           "\(snaps) local snapshots are holding \"purgeable\" space.",
                                           "\(snaps) локальных снимков занимают «очищаемое» место."),
                                 level: .info, panel: .maintenance))
        }

        if mem.fraction > 0.85 || mem.swapUsed > 2_000_000_000 {
            tips.append(SmartTip(id: "ram", icon: "memorychip",
                                 title: T("Xotira bosimi yuqori", "High memory pressure", "Высокая нагрузка на память"),
                                 detail: T("RAM \(Int(mem.fraction * 100))% band, swap \(Format.mem(mem.swapUsed)). Og'ir ilovalarni yoping.",
                                           "RAM \(Int(mem.fraction * 100))% used, swap \(Format.mem(mem.swapUsed)). Close heavy apps.",
                                           "RAM занята на \(Int(mem.fraction * 100))%, swap \(Format.mem(mem.swapUsed)). Закройте тяжёлые приложения."),
                                 level: .warn, panel: .memory))
        }

        let agents = thirdPartyAgents()
        if agents > 8 {
            tips.append(SmartTip(id: "agents", icon: "power",
                                 title: T("Fon agentlari ko'p", "Many background agents", "Много фоновых агентов"),
                                 detail: T("\(agents) ta uchinchi tomon agenti ishga tushishni sekinlashtirishi mumkin.",
                                           "\(agents) third-party agents may slow down startup.",
                                           "\(agents) сторонних агентов могут замедлять запуск."),
                                 level: .info, panel: .startup))
        }

        let days = Int(ProcessInfo.processInfo.systemUptime / 86400)
        if days >= 14 {
            tips.append(SmartTip(id: "uptime", icon: "arrow.clockwise",
                                 title: T("Qayta yuklash vaqti", "Time to restart", "Пора перезагрузить"),
                                 detail: T("Mac \(days) kundan beri o'chmagan. Qayta yuklash xotira va keshlarni yangilaydi.",
                                           "Your Mac has been up for \(days) days. A restart refreshes memory and caches.",
                                           "Mac работает \(days) дней без перезагрузки. Перезагрузка освежит память и кэши."),
                                 level: .info, panel: nil))
        }

        return tips.sorted { $0.level.rawValue != $1.level.rawValue ? $0.level.rawValue > $1.level.rawValue : $0.size > $1.size }
    }
}

@MainActor
final class SmartModel: ObservableObject {
    @Published var tips: [SmartTip] = []
    @Published var analyzing = false
    @Published var lastAuto: String?
    @Published var autoClean: Bool = UserDefaults.standard.bool(forKey: "autoClean") {
        didSet { UserDefaults.standard.set(autoClean, forKey: "autoClean"); if autoClean { requestNotifications() } }
    }
    @Published var lowDiskAlert: Bool = UserDefaults.standard.object(forKey: "lowDiskAlert") as? Bool ?? true {
        didSet { UserDefaults.standard.set(lowDiskAlert, forKey: "lowDiskAlert"); if lowDiskAlert { requestNotifications() } }
    }
    private var loop: Task<Void, Never>?
    private var cpuLoop: Task<Void, Never>?
    /// pid → ketma-ket necha tekshiruvda og'ir bo'lgan
    private var hot: [Int32: Int] = [:]
    private var alerted: [String: Date] = [:]
    @Published var cpuAlerts: Bool = UserDefaults.standard.object(forKey: "cpuAlerts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cpuAlerts, forKey: "cpuAlerts"); if cpuAlerts { requestNotifications() } }
    }

    var score: Int {
        // 100 — ideal. Har bir maslahat ballni pasaytiradi.
        let penalty = tips.reduce(0) { $0 + ($1.level == .critical ? 30 : $1.level == .warn ? 12 : 4) }
        return max(0, 100 - penalty)
    }

    private var lastRun = Date.distantPast

    /// Og'ir tahlil 5 daqiqada ko'pi bilan bir marta (force — tozalashdan keyin).
    func analyze(memory: MemoryModel, force: Bool = false) {
        guard !analyzing, force || Date().timeIntervalSince(lastRun) > 300 else { return }
        lastRun = Date()
        analyzing = true
        Task {
            // Diskni shu yerda o'lchaymiz — birinchi ochilishda MemoryModel hali 0 bo'lishi mumkin
            let t = await Task.detached(priority: .utility) { () -> [SmartTip] in
                let d = SystemStats.disk()
                return SmartAnalyzer.analyze(diskTotal: d.total, diskFree: d.free, mem: SystemStats.memory())
            }.value
            self.tips = t
            self.analyzing = false
        }
    }

    /// Fon rejimi: har 30 daqiqada disk tekshiruvi, kuniga bir marta avtomatik tozalash muddati tekshiruvi.
    func startBackground() {
        guard loop == nil else { return }
        if lowDiskAlert || autoClean { requestNotifications() }
        // Og'ir jarayonlar kuzatuvi: daqiqada bir marta bitta `ps` — deyarli bepul
        cpuLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self?.cpuTick()
            }
        }
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            while !Task.isCancelled {
                await self?.backgroundTick()
                try? await Task.sleep(nanoseconds: 1_800_000_000_000)
            }
        }
    }

    /// 3 daqiqadan ortiq 80%+ CPU yeyotgan jarayon haqida ogohlantiradi (har jarayon uchun soatiga 1 marta).
    private func cpuTick() async {
        guard cpuAlerts else { hot = [:]; return }
        let procs = await Task.detached(priority: .background) { SystemStats.topProcesses(limit: 8, byCPU: true) }.value
        let me = ProcessInfo.processInfo.processIdentifier
        // Siz hozir ishlayotgan ilova (masalan, Logic'da bounce) — ogohlantirmaymiz
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ignore: Set<String> = ["kernel_task", "WindowServer", "mds_stores", "mds", "mdworker_shared",
                                   "backupd", "photoanalysisd", "softwareupdated", "Logic Pro", "Logic Pro X"]
        var next: [Int32: Int] = [:]
        // %cpu — bitta yadro bo'yicha; 150%+ = 1,5 yadro to'liq band
        for p in procs where p.cpu >= 150 && p.pid != me && p.pid != front && !ignore.contains(p.name) {
            let n = (hot[p.pid] ?? 0) + 1
            next[p.pid] = n
            if n >= 3, Date().timeIntervalSince(alerted[p.name] ?? .distantPast) > 3600 {
                alerted[p.name] = Date()
                notify(T("\(p.name) CPU'ni band qilmoqda", "\(p.name) is hogging the CPU", "\(p.name) нагружает CPU"),
                       T("\(Int(p.cpu))% — 3 daqiqadan beri. Max Clean → Tezlik bo'limida yopishingiz mumkin.",
                         "\(Int(p.cpu))% for 3+ minutes. You can quit it in Max Clean → Speed.",
                         "\(Int(p.cpu))% уже 3+ минуты. Закрыть можно в Max Clean → Скорость."))
            }
        }
        hot = next
    }

    private func backgroundTick() async {
        let d = SystemStats.disk()
        let defaults = UserDefaults.standard
        if lowDiskAlert, d.free < 10_000_000_000 {
            let last = defaults.double(forKey: "lastDiskAlert")
            if Date().timeIntervalSince1970 - last > 6 * 3600 {
                defaults.set(Date().timeIntervalSince1970, forKey: "lastDiskAlert")
                notify(T("Disk deyarli to'la", "Disk is almost full", "Диск почти заполнен"),
                       T("Atigi \(Format.bytes(d.free)) bo'sh qoldi. Max Clean bilan tozalang.",
                         "Only \(Format.bytes(d.free)) left. Clean up with Max Clean.",
                         "Осталось \(Format.bytes(d.free)). Очистите с Max Clean."))
            }
        }
        if autoClean {
            let last = defaults.double(forKey: "lastAutoClean")
            if Date().timeIntervalSince1970 - last > 7 * 86400 {
                defaults.set(Date().timeIntervalSince1970, forKey: "lastAutoClean")
                let ctx = SmartContext.current()
                let freed = await Task.detached(priority: .background) { SmartModel.runSafeClean(ctx: ctx) }.value
                lastAuto = Format.bytes(freed)
                if freed > 0 {
                    notify(T("Avtomatik tozalash", "Auto-clean", "Автоочистка"),
                           T("\(Format.bytes(freed)) kesh va log tozalandi.",
                             "\(Format.bytes(freed)) of caches and logs removed.",
                             "Удалено \(Format.bytes(freed)) кэша и логов."))
                }
            }
        }
    }

    /// Faqat xavfsiz toifalar: keshlar, loglar, Electron keshi, Xcode/Simulator, paket menejerlari.
    nonisolated static func runSafeClean(ctx: SmartContext) -> Int64 {
        let safe = JunkSpec.all.filter { spec in
            if case .electronCaches = spec.mode { return true }
            guard let r = spec.roots.first else { return false }
            return r.hasPrefix("~/Library/Caches") || r.hasPrefix("~/Library/Logs")
                || r.hasPrefix("~/Library/Developer") || r.hasPrefix("~/.npm") || r.hasPrefix("~/.gradle")
        }
        // Aqlli qoidalar bo'yicha tanlanganlarini o'chiramiz (ochiq ilovalar keshi va siz qoldirganlar tegilmaydi)
        let items = safe.map { JunkScanner.scan($0, ctx: ctx) }.flatMap(\.items).filter(\.selected)
        return Remover.remove(items, permanently: true).freed
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        let r = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(r)
    }
}

/// Bosh sahifadagi "Aqlli maslahatlar" bloki.
struct SmartTipsCard: View {
    @EnvironmentObject var smart: SmartModel
    let go: (Panel) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "wand.and.stars").foregroundStyle(Theme.accentGradient)
                    Text(T("Aqlli maslahatlar", "Smart Assistant", "Умный помощник")).font(.headline)
                    Spacer()
                    if smart.analyzing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(T("Salomatlik: \(smart.score)/100", "Health: \(smart.score)/100", "Здоровье: \(smart.score)/100"))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill((smart.score >= 80 ? Theme.green : smart.score >= 50 ? Theme.orange : Theme.red).opacity(0.2)))
                            .foregroundColor(smart.score >= 80 ? Theme.green : smart.score >= 50 ? Theme.orange : Theme.red)
                    }
                }
                if smart.tips.isEmpty && !smart.analyzing {
                    Label(T("Mac yaxshi holatda. Hozircha maslahat yo'q.", "Your Mac is in good shape. No suggestions right now.",
                            "Mac в хорошем состоянии. Советов пока нет."), systemImage: "checkmark.seal.fill")
                        .foregroundColor(Theme.green)
                }
                ForEach(smart.tips.prefix(5)) { tip in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(color(tip.level).opacity(0.18)).frame(width: 34, height: 34)
                            Image(systemName: tip.icon).foregroundColor(color(tip.level))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title).font(.subheadline.weight(.semibold))
                            Text(tip.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if let p = tip.panel {
                            Button(T("Hal qilish", "Fix", "Исправить")) { go(p) }.buttonStyle(GhostButtonStyle())
                        }
                    }
                }
            }
        }
    }

    func color(_ l: SmartTip.Level) -> Color {
        switch l {
        case .critical: return Theme.red
        case .warn: return Theme.orange
        case .info: return Theme.accent
        }
    }
}
