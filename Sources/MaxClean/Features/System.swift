import SwiftUI
import AppKit
import Darwin

// MARK: - Xotira, CPU, disk monitori

struct MemStats: Sendable {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var used: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct ProcInfo: Identifiable, Sendable {
    var id: Int32 { pid }
    let pid: Int32
    let mem: UInt64
    let cpu: Double
    let name: String
}

enum SystemStats {
    static func memory() -> MemStats {
        var s = MemStats()
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return s }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        s.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        s.wired = UInt64(stats.wire_count) * page
        s.compressed = UInt64(stats.compressor_page_count) * page
        s.cached = (UInt64(stats.external_page_count) + purgeable) * page
        s.used = s.app + s.wired + s.compressed

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { s.swapUsed = swap.xsu_used }
        return s
    }

    static func disk() -> (total: Int64, free: Int64) {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                                          .volumeAvailableCapacityForImportantUsageKey])
        return (Int64(v?.volumeTotalCapacity ?? 0), v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    static func load() -> Double {
        var l = [Double](repeating: 0, count: 3)
        getloadavg(&l, 3)
        return l[0]
    }

    static func topProcesses(limit: Int = 12, byCPU: Bool = false) -> [ProcInfo] {
        let out = Shell.run("/bin/ps", ["-Aceo", "pid=,rss=,%cpu=,comm=", byCPU ? "-r" : "-m"]).out
        var r: [ProcInfo] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let rss = UInt64(parts[1]) else { continue }
            let cpu = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
            r.append(ProcInfo(pid: pid, mem: rss * 1024, cpu: cpu, name: String(parts[3])))
            if r.count >= limit { break }
        }
        return r
    }
}

@MainActor
final class MemoryModel: ObservableObject {
    @Published var mem = MemStats()
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var loadAvg: Double = 0
    @Published var processes: [ProcInfo] = []
    @Published var message: String?
    private var loop: Task<Void, Never>?
    private var tick = 0
    /// Jarayonlar ro'yxati faqat «Tezlik» ekrani ochiq bo'lganda yangilanadi (yengil ishlash uchun).
    var wantsProcesses = false

    var diskFraction: Double { diskTotal == 0 ? 0 : Double(diskTotal - diskFree) / Double(diskTotal) }
    var cpuFraction: Double { min(loadAvg / Double(ProcessInfo.processInfo.activeProcessorCount), 1) }

    init() { start() }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func refresh() async {
        let snap = await Task.detached(priority: .utility) { () -> (MemStats, Int64, Int64, Double) in
            let d = SystemStats.disk()
            return (SystemStats.memory(), d.total, d.free, SystemStats.load())
        }.value
        // Faqat o'zgarganda e'lon qilamiz — keraksiz qayta chizish bo'lmasin
        if abs(Int64(clamping: snap.0.used) - Int64(clamping: mem.used)) > 20_000_000 || snap.0.swapUsed != mem.swapUsed { mem = snap.0 }
        if snap.1 != diskTotal { diskTotal = snap.1 }
        if abs(snap.2 - diskFree) > 50_000_000 { diskFree = snap.2 }
        if abs(snap.3 - loadAvg) > 0.05 { loadAvg = snap.3 }
        tick += 1
        if wantsProcesses && tick % 2 == 1 {
            processes = await Task.detached { SystemStats.topProcesses() }.value
        }
    }

    func freeRAM() {
        let before = mem.used
        let r = Admin.run("/usr/sbin/purge")
        if r.ok {
            mem = SystemStats.memory()
            let freed = before > mem.used ? before - mem.used : 0
            message = T("RAM bo'shatildi: \(Format.mem(freed))", "RAM freed: \(Format.mem(freed))", "Освобождено RAM: \(Format.mem(freed))")
        } else {
            message = r.out
        }
    }

    func quit(_ p: ProcInfo, force: Bool = false) {
        if let app = NSRunningApplication(processIdentifier: p.pid) {
            _ = force ? app.forceTerminate() : app.terminate()
        } else {
            kill(p.pid, force ? SIGKILL : SIGTERM)
        }
        message = T("\(p.name) yopildi.", "\(p.name) closed.", "\(p.name) закрыт.")
    }
}

struct MemoryView: View {
    @EnvironmentObject var model: MemoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "memorychip", title: T("Tezlik va xotira", "Speed & Memory", "Скорость и память"),
                       subtitle: T("RAM, CPU yuklamasi va eng ko'p xotira yeyotgan jarayonlar", "RAM, CPU load and the most memory-hungry processes", "RAM, нагрузка CPU и самые прожорливые процессы")) {
                Button(T("RAM bo'shatish", "Free up RAM", "Освободить RAM")) { model.freeRAM() }.buttonStyle(GlowButtonStyle())
            }
            if let m = model.message { Text(m).foregroundColor(Theme.green) }
            HStack(spacing: 14) {
                Card {
                    HStack(spacing: 30) {
                        Ring(progress: model.mem.fraction, title: "RAM",
                             value: Format.mem(model.mem.used), size: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            stat(T("Jami", "Total", "Всего"), model.mem.total)
                            stat(T("Ilovalar", "Apps", "Приложения"), model.mem.app)
                            stat("Wired", model.mem.wired)
                            stat(T("Siqilgan", "Compressed", "Сжато"), model.mem.compressed)
                            stat(T("Kesh fayllar", "Cached files", "Кэш-файлы"), model.mem.cached)
                            stat("Swap", model.mem.swapUsed)
                        }
                    }
                }
                Card {
                    HStack(spacing: 30) {
                        Ring(progress: model.cpuFraction, title: T("CPU yuklama", "CPU load", "Нагрузка CPU"),
                             value: String(format: "%.1f", model.loadAvg), size: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(T("Yadrolar: \(ProcessInfo.processInfo.activeProcessorCount)", "Cores: \(ProcessInfo.processInfo.activeProcessorCount)", "Ядра: \(ProcessInfo.processInfo.activeProcessorCount)"))
                            Text(T("Ishlash vaqti: \(uptime)", "Uptime: \(uptime)", "Время работы: \(uptime)"))
                            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text(T("Ko'p xotira ishlatayotganlar", "Top memory consumers", "Больше всего памяти")).font(.headline)
            List(model.processes) { p in
                HStack {
                    Text(p.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%% CPU", p.cpu)).font(.caption).foregroundStyle(.secondary).frame(width: 80)
                    Text(Format.mem(p.mem)).font(.system(.body, design: .monospaced)).frame(width: 90, alignment: .trailing)
                    Button(T("Yopish", "Quit", "Закрыть")) { model.quit(p) }.buttonStyle(.borderless)
                    Button(T("Majburan", "Force quit", "Принудительно")) { model.quit(p, force: true) }.buttonStyle(.borderless).foregroundColor(Theme.orange)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(24)
        .onAppear {
            model.wantsProcesses = true
            Task { await model.refresh() }
        }
        .onDisappear { model.wantsProcesses = false }
    }

    var uptime: String {
        let t = Int(ProcessInfo.processInfo.systemUptime)
        return T("\(t / 86400) kun \(t % 86400 / 3600) soat", "\(t / 86400) d \(t % 86400 / 3600) h", "\(t / 86400) д \(t % 86400 / 3600) ч")
    }

    func stat(_ title: String, _ v: UInt64) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(Format.mem(v)).font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Texnik xizmat

struct MaintTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let admin: Bool
    let command: String
}

@MainActor
final class MaintenanceModel: ObservableObject {
    enum Status: Equatable { case idle, running, done(String), failed(String) }
    @Published var status: [String: Status] = [:]

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    var tasks: [MaintTask] { [
        MaintTask(id: "ram", title: T("RAM bo'shatish", "Free up RAM", "Освободить RAM"), detail: T("Faol bo'lmagan xotirani tozalaydi (purge)", "Purges inactive memory", "Очищает неактивную память (purge)"),
                  icon: "memorychip", admin: true, command: "/usr/sbin/purge"),
        MaintTask(id: "snap", title: T("Time Machine lokal snapshotlari", "Time Machine local snapshots", "Локальные снимки Time Machine"),
                  detail: T("«Purgeable» joyni darhol qaytaradi — ko'pincha o'nlab GB", "Reclaims \"purgeable\" space right away — often tens of GB", "Сразу возвращает «очищаемое» место — часто десятки ГБ"),
                  icon: "clock.arrow.circlepath", admin: true,
                  command: "tmutil thinlocalsnapshots / 999999999999 4; tmutil listlocalsnapshots /"),
        MaintTask(id: "dns", title: T("DNS keshini tozalash", "Flush DNS cache", "Сбросить кэш DNS"), detail: T("Sayt ochilmasa yoki internet g'alati ishlasa", "When sites won't load or the network acts up", "Если сайты не открываются или сеть сбоит"),
                  icon: "network", admin: true, command: "dscacheutil -flushcache; killall -HUP mDNSResponder"),
        MaintTask(id: "spot", title: T("Spotlight indeksini qayta qurish", "Reindex Spotlight", "Переиндексировать Spotlight"), detail: T("Qidiruv noto'g'ri ishlasa", "When search gives wrong results", "Если поиск работает неправильно"),
                  icon: "magnifyingglass", admin: true, command: "mdutil -E /"),
        MaintTask(id: "ls", title: T("Launch Services bazasini tiklash", "Rebuild Launch Services", "Перестроить Launch Services"),
                  detail: T("«Ochish» menyusidagi takror/eski ilovalarni tozalaydi", "Removes duplicates from the \"Open With\" menu", "Убирает дубли в меню «Открыть в программе»"),
                  icon: "list.bullet.rectangle", admin: false,
                  command: "\(MaintenanceModel.lsregister) -kill -r -domain local -domain system -domain user"),
        MaintTask(id: "ql", title: T("Quick Look keshini tozalash", "Reset Quick Look cache", "Сбросить кэш Quick Look"), detail: T("Eskizlar noto'g'ri ko'rinsa", "When thumbnails look wrong", "Если миниатюры отображаются неверно"),
                  icon: "eye", admin: false, command: "qlmanage -r cache; qlmanage -r"),
        MaintTask(id: "font", title: T("Shrift keshini tozalash", "Clear font cache", "Очистить кэш шрифтов"), detail: T("Shriftlar buzuq ko'rinsa (qayta kirish kerak)", "When fonts look broken (re-login required)", "Если шрифты отображаются криво (нужен перелогин)"),
                  icon: "textformat", admin: false, command: "atsutil databases -removeUser"),
        MaintTask(id: "disk", title: T("Diskni tekshirish", "Verify disk", "Проверить диск"), detail: T("APFS tuzilmasini tekshiradi (faqat o'qish)", "Checks the APFS structure (read-only)", "Проверяет структуру APFS (только чтение)"),
                  icon: "internaldrive", admin: false, command: "diskutil verifyVolume /"),
        MaintTask(id: "dock", title: T("Dock va Finder'ni qayta ishga tushirish", "Restart Dock & Finder", "Перезапустить Dock и Finder"), detail: T("Interfeys qotib qolsa", "When the interface freezes", "Если интерфейс завис"),
                  icon: "dock.rectangle", admin: false, command: "killall Dock; killall Finder")
    ] }

    func run(_ t: MaintTask) {
        status[t.id] = .running
        if t.admin {
            let r = Admin.run(t.command)
            status[t.id] = r.ok ? .done(r.out) : .failed(r.out)
            History.add("XIZMAT\t\(t.title)\t\(r.ok ? "OK" : "XATO")")
        } else {
            let cmd = t.command
            Task {
                let r = await Task.detached { Shell.zsh(cmd) }.value
                self.status[t.id] = r.status == 0 ? .done(r.out) : .failed(r.out)
                History.add("XIZMAT\t\(t.title)\t\(r.status == 0 ? "OK" : "XATO")")
            }
        }
    }
}

struct MaintenanceView: View {
    @EnvironmentObject var model: MaintenanceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "wrench.and.screwdriver", title: T("Texnik xizmat", "Maintenance", "Обслуживание"),
                       subtitle: T("Mac'ni tezlashtiruvchi va muammolarni tuzatuvchi skriptlar", "Scripts that speed up your Mac and fix common issues", "Скрипты для ускорения Mac и исправления проблем"))
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.tasks) { t in
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: t.icon).font(.title2).foregroundStyle(Theme.accentGradient).frame(width: 30)
                                    VStack(alignment: .leading) {
                                        Text(t.title).font(.headline)
                                        Text(t.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if t.admin { Image(systemName: "lock.fill").foregroundStyle(.secondary).help(T("Parol so'raladi", "Requires password", "Нужен пароль")) }
                                }
                                HStack {
                                    statusView(model.status[t.id] ?? .idle)
                                    Spacer()
                                    Button(T("Bajarish", "Run", "Запустить")) { model.run(t) }
                                        .buttonStyle(GhostButtonStyle())
                                        .disabled(model.status[t.id] == .running)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
    }

    @ViewBuilder func statusView(_ s: MaintenanceModel.Status) -> some View {
        switch s {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .done(let out):
            Label(T("Bajarildi", "Done", "Готово"), systemImage: "checkmark.circle.fill").foregroundColor(Theme.green)
                .help(out.isEmpty ? "OK" : out)
        case .failed(let out):
            Label(T("Xato", "Error", "Ошибка"), systemImage: "exclamationmark.triangle.fill").foregroundColor(Theme.orange)
                .help(out)
        }
    }
}

// MARK: - Space Lens (disk xaritasi)

struct SizedEntry: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let isDir: Bool
}

@MainActor
final class SpaceModel: ObservableObject {
    @Published var stack: [URL] = []
    @Published var entries: [SizedEntry] = []
    @Published var loading = false
    @Published var message: String?

    var current: URL? { stack.last }
    var total: Int64 { entries.reduce(0) { $0 + $1.size } }

    func open(_ url: URL, push: Bool = true) {
        if push { stack.append(url) }
        loading = true
        entries = []
        Task {
            let r = await Task.detached(priority: .userInitiated) { () async -> [SizedEntry] in
                var kids = FS.children(url)
                if url.path == "/" {
                    kids.removeAll { ["/Volumes", "/System/Volumes", "/dev", "/cores", "/private/var/vm"].contains($0.path) }
                }
                return await withTaskGroup(of: SizedEntry.self) { g in
                    for c in kids {
                        g.addTask { SizedEntry(url: c, size: FS.allocatedSize(of: c), isDir: FS.isDir(c) && c.pathExtension != "app") }
                    }
                    var arr: [SizedEntry] = []
                    for await e in g { arr.append(e) }
                    return arr.sorted { $0.size > $1.size }
                }
            }.value
            if self.current == url { self.entries = r; self.loading = false }
        }
    }

    func back() {
        guard stack.count > 1 else { return }
        stack.removeLast()
        if let u = stack.last { open(u, push: false) }
    }

    func jump(to index: Int) {
        guard index < stack.count else { return }
        stack = Array(stack.prefix(index + 1))
        open(stack[index], push: false)
    }

    func trash(_ e: SizedEntry) {
        let r = Remover.remove([FileEntry(url: e.url, size: e.size, modified: nil, selected: true)], permanently: false)
        if r.failed.isEmpty {
            entries.removeAll { $0.id == e.id }
            message = T("\(e.url.lastPathComponent) Savatga yuborildi (\(Format.bytes(e.size))).", "\(e.url.lastPathComponent) moved to Trash (\(Format.bytes(e.size))).", "\(e.url.lastPathComponent) перемещено в Корзину (\(Format.bytes(e.size))).")
        } else {
            message = T("O'chirib bo'lmadi (himoyalangan yoki ruxsat yo'q).", "Couldn't remove (protected or no permission).", "Не удалось удалить (защищено или нет доступа).")
        }
    }
}

struct SpaceLensView: View {
    @EnvironmentObject var model: SpaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "circle.hexagongrid", title: T("Disk xaritasi", "Disk Map", "Карта диска"),
                       subtitle: T("Joy qayerga ketganini papkama-papka ko'ring", "See where your space goes, folder by folder", "Смотрите, куда уходит место, папка за папкой")) {
                HStack {
                    Button(T("Uy papkasi", "Home", "Домой")) { model.stack = []; model.open(FS.home) }.buttonStyle(GhostButtonStyle())
                    Button(T("Butun disk", "Whole disk", "Весь диск")) { model.stack = []; model.open(URL(fileURLWithPath: "/")) }.buttonStyle(GhostButtonStyle())
                    Button(T("Tanlash…", "Choose…", "Выбрать…")) { if let u = pickFolder() { model.stack = []; model.open(u) } }.buttonStyle(GhostButtonStyle())
                }
            }
            if !model.stack.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button { model.back() } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.borderless).disabled(model.stack.count < 2)
                        ForEach(Array(model.stack.enumerated()), id: \.offset) { i, u in
                            Button(u.path == "/" ? "Macintosh HD" : u.lastPathComponent) { model.jump(to: i) }
                                .buttonStyle(.borderless)
                            if i < model.stack.count - 1 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(T("Jami: \(Format.bytes(model.total))", "Total: \(Format.bytes(model.total))", "Всего: \(Format.bytes(model.total))")).foregroundStyle(.secondary)
                    }
                }
            }
            if let m = model.message { Text(m).foregroundColor(Theme.green) }
            if model.stack.isEmpty {
                EmptyState(icon: "circle.hexagongrid", text: T("Boshlash uchun yuqoridan joyni tanlang", "Pick a location above to start", "Выберите место сверху, чтобы начать"))
            } else if model.loading {
                ProgressView(T("Hajmlar hisoblanmoqda…", "Calculating sizes…", "Подсчёт размеров…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.entries) { e in
                    HStack(spacing: 10) {
                        Image(nsImage: IconCache.icon(e.url.path)).resizable().frame(width: 22, height: 22)
                        Text(e.url.lastPathComponent).lineLimit(1).frame(width: 260, alignment: .leading)
                        SizeBar(fraction: model.total == 0 ? 0 : Double(e.size) / Double(model.total))
                        Text(Format.bytes(e.size)).font(.system(.body, design: .monospaced)).frame(width: 90, alignment: .trailing)
                        if e.isDir { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if e.isDir { model.open(e.url) } }
                    .contextMenu {
                        Button(T("Finder'da ko'rsatish", "Show in Finder", "Показать в Finder")) { FS.reveal(e.url) }
                        Button(T("Savatga yuborish", "Move to Trash", "В Корзину")) { model.trash(e) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
    }
}
