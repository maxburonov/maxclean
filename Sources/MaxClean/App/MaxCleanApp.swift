import SwiftUI
import AppKit
import ServiceManagement

@main
struct MaxCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let m = AppModels.shared
    @AppStorage("lang") private var lang = Lang.systemDefault.rawValue

    var body: some Scene {
        WindowGroup("Max Clean", id: "main") {
            RootView()
                .environmentObject(m)
                .environmentObject(m.junk)
                .environmentObject(m.memory)
                .environmentObject(m.large)
                .environmentObject(m.dups)
                .environmentObject(m.dev)
                .environmentObject(m.uninstaller)
                .environmentObject(m.startup)
                .environmentObject(m.maintenance)
                .environmentObject(m.space)
                .environmentObject(m.settings)
                .environmentObject(m.firewall)
                .environmentObject(m.smart)
                .environmentObject(m.updates)
                .environmentObject(m.protection)
                .environmentObject(m.updater)
                .environmentObject(m.disk)
                .environmentObject(m.smartScan)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
                .id(lang) // til almashganda butun interfeys qayta chiziladi
        }
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

// MARK: - Bo'limlar

enum Panel: String, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard, junk, large, duplicates, dev, uninstaller, updates, startup, protection, firewall, memory, maintenance, analyzer, space, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return T("Aqlli tekshiruv", "Smart Scan", "Умная проверка")
        case .junk: return T("Tizim keraksizlari", "System Junk", "Системный мусор")
        case .large: return T("Katta fayllar", "Large Files", "Большие файлы")
        case .duplicates: return T("Dublikatlar", "Duplicates", "Дубликаты")
        case .dev: return T("Dasturchi keraksizlari", "Developer Junk", "Мусор разработчика")
        case .uninstaller: return T("Ilovalarni o'chirish", "Uninstaller", "Деинсталлятор")
        case .startup: return T("Avto-ishga tushish", "Launch Agents", "Автозапуск")
        case .firewall: return T("Internet blokirovkasi", "App Firewall", "Блокировка сети")
        case .memory: return T("Tezlik va xotira", "Speed & Memory", "Скорость и память")
        case .maintenance: return T("Texnik xizmat", "Maintenance", "Обслуживание")
        case .space: return T("Disk xaritasi", "Disk Map", "Карта диска")
        case .updates: return T("Yangilanishlar", "Updates", "Обновления")
        case .analyzer: return T("Disk tahlili", "Disk Analyzer", "Анализ диска")
        case .protection: return T("Himoya", "Protection", "Защита")
        case .settings: return T("Sozlamalar", "Settings", "Настройки")
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "display"
        case .junk: return "trash.circle"
        case .large: return "doc.badge.ellipsis"
        case .duplicates: return "doc.on.doc"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .uninstaller: return "xmark.app"
        case .startup: return "power"
        case .firewall: return "network.slash"
        case .memory: return "memorychip"
        case .maintenance: return "wrench.and.screwdriver"
        case .space: return "circle.hexagongrid"
        case .updates: return "arrow.down.app"
        case .analyzer: return "chart.bar.doc.horizontal"
        case .protection: return "checkmark.shield"
        case .settings: return "gearshape"
        }
    }
}

struct PanelGroup: Identifiable {
    let title: String
    let items: [Panel]
    var id: String { title + items.map(\.rawValue).joined() }
    static var all: [PanelGroup] {
        [
            PanelGroup(title: "", items: [.dashboard]),
            PanelGroup(title: T("Tozalash", "Cleanup", "Очистка"), items: [.junk, .large, .duplicates, .dev]),
            PanelGroup(title: T("Ilovalar", "Applications", "Приложения"), items: [.uninstaller, .updates, .startup]),
            PanelGroup(title: T("Xavfsizlik", "Security", "Безопасность"), items: [.protection, .firewall]),
            PanelGroup(title: T("Tezlik", "Speed", "Скорость"), items: [.memory, .maintenance]),
            PanelGroup(title: T("Disk", "Disk", "Диск"), items: [.analyzer, .space])
        ]
    }
}

struct RootView: View {
    @SceneStorage("panel") private var selection: Panel = .dashboard
    @EnvironmentObject var models: AppModels
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)
                .frame(width: 236)
            ZStack {
                AnimatedBackground()
                detail
                    .id(selection)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                            removal: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: selection)
        }
        .ignoresSafeArea()
        .onAppear {
            models.openMain = { openWindow(id: "main") }
            NSApp.setActivationPolicy(.regular)
        }
        .onReceive(models.$requestedPanel) { p in
            guard let p else { return }
            selection = p
            DispatchQueue.main.async { models.requestedPanel = nil }
        }
    }

    @ViewBuilder var detail: some View {
        switch selection {
        case .dashboard: DashboardView(go: { selection = $0 })
        case .junk: JunkView()
        case .large: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .dev: DevView()
        case .uninstaller: UninstallerView()
        case .startup: StartupView()
        case .firewall: FirewallView()
        case .memory: MemoryView()
        case .maintenance: MaintenanceView()
        case .space: SpaceLensView()
        case .updates: UpdatesView()
        case .analyzer: DiskAnalyzerView(go: { selection = $0 })
        case .protection: ProtectionView()
        case .settings: SettingsView()
        }
    }
}

struct Sidebar: View {
    @Binding var selection: Panel
    @EnvironmentObject var updates: UpdatesModel
    @EnvironmentObject var protection: ProtectionModel
    @Namespace private var ns
    @EnvironmentObject var junk: JunkModel
    @EnvironmentObject var firewall: FirewallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                Text("Max Clean").font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .padding(.horizontal, 18)
            .padding(.top, 44) // svetofor tugmalari uchun joy
            .padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(PanelGroup.all) { g in
                        if !g.title.isEmpty {
                            Text(g.title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.38))
                                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
                        }
                        ForEach(g.items) { p in
                            SidebarItem(panel: p, selected: selection == p, badge: badge(for: p), ns: ns) { selection = p }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            SidebarItem(panel: .settings, selected: selection == .settings, badge: nil, ns: ns) { selection = .settings }
                .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Theme.sidebar
                LinearGradient(colors: [Theme.accent.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
            }
        )
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1), alignment: .trailing)
    }

    func badge(for p: Panel) -> String? {
        switch p {
        case .updates: return updates.updates.isEmpty ? nil : "\(updates.updates.count)"
        case .protection: return protection.dangerCount > 0 ? "\(protection.dangerCount)" : nil
        case .junk: return junk.scannedOnce && junk.total > 0 ? Format.bytes(junk.total) : nil
        case .firewall: return firewall.blocked.isEmpty ? nil : "\(firewall.blocked.count)"
        default: return nil
        }
    }
}

struct SidebarItem: View {
    let panel: Panel
    let selected: Bool
    let badge: String?
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: panel.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accentGradient))
                    .frame(width: 20)
                    .scaleEffect(hover && !selected ? 1.12 : 1)
                Text(panel.title).font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundColor(.white.opacity(selected ? 1 : 0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.25 : 0.10)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                if selected {
                    // Tanlov "pilyulasi" bo'limlar orasida silliq siljiydi
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.6), Theme.accent2.opacity(0.32)],
                                             startPoint: .leading, endPoint: .trailing))
                        .shadow(color: Theme.accent.opacity(0.35), radius: 8)
                        .matchedGeometryEffect(id: "selection", in: ns)
                } else if hover {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selected)
    }
}

// MARK: - Bosh sahifa

struct DashboardView: View {
    @EnvironmentObject var scan: SmartScanModel
    @EnvironmentObject var dev: DevModel
    @State private var confirmRun = false
    @EnvironmentObject var updater: AutoUpdater
    @EnvironmentObject var junk: JunkModel
    @EnvironmentObject var memory: MemoryModel
    @EnvironmentObject var smart: SmartModel
    let go: (Panel) -> Void
    @State private var fda = Permissions.hasFullDiskAccess
    @State private var trashSize: Int64?
    @State private var confirmEmpty = false
    @State private var emptyingTrash = false
    @State private var trashMeasuredAt = Date.distantPast

    private func measureTrash(force: Bool = false) {
        guard fda else { return } // ruxsatsiz Savat o'lchanmaydi
        guard force || Date().timeIntervalSince(trashMeasuredAt) > 120 else { return }
        trashMeasuredAt = Date()
        Task {
            let s = await Task.detached(priority: .utility) { TrashInfo.size() }.value
            withAnimation { trashSize = s }
        }
    }

    private func emptyTrash() {
        emptyingTrash = true
        Task {
            let freed = await Task.detached(priority: .userInitiated) { TrashInfo.empty() }.value
            emptyingTrash = false
            junk.lastFreed = freed
            if junk.scannedOnce { junk.scan() } // eskirgan ro'yxatni yangilaymiz
            withAnimation(.spring()) { junk.justCleaned = true }
            measureTrash(force: true)
            smart.analyze(memory: memory, force: true)
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation { junk.justCleaned = false }
        }
    }

    var headline: String {
        switch scan.phase {
        case .scanning: return T("Mac tekshirilmoqda…", "Checking your Mac…", "Проверяем Mac…")
        case .results: return T("\(Format.bytes(scan.estimate)) bo'shatish mumkin", "\(Format.bytes(scan.estimate)) can be freed",
                                "Можно освободить \(Format.bytes(scan.estimate))")
        case .running: return T("Bajarilmoqda…", "Working…", "Выполняется…")
        case .done: return scan.freedReal > 0
            ? T("Diskda \(Format.bytes(scan.freedReal)) bo'shadi!", "\(Format.bytes(scan.freedReal)) freed on disk!",
                "На диске освобождено \(Format.bytes(scan.freedReal))!")
            : T("Tayyor!", "All done!", "Готово!")
        case .idle: return T("Mac'ingizni tozalaymizmi?", "Ready to clean your Mac?", "Почистим ваш Mac?")
        }
    }

    var subline: String {
        switch scan.phase {
        case .scanning: return scan.step
        case .running: return scan.step
        case .results: return T("Keraksizlarni tanlang va «Bajarish»ni bosing — hammasi bir martada",
                                "Pick what to include and press Run — everything at once",
                                "Выберите нужное и нажмите «Выполнить» — всё за один раз")
        case .done: return T("Bu — taxmin emas, diskda o'lchangan haqiqiy natija", "Measured on disk — not an estimate",
                             "Измерено на диске — не оценка")
        case .idle: return T("Bitta tugma: keraksiz fayllar, Savat, snapshotlar, RAM, himoya, yangilanishlar va disk tahlili",
                             "One click: junk, Trash, snapshots, RAM, protection, updates and disk analysis",
                             "Одна кнопка: мусор, Корзина, снимки, RAM, защита, обновления и анализ диска")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if updater.isAvailable {
                    UpdateCard(compact: true).fadeIn(0)
                }
                if !fda {
                    Card {
                        HStack {
                            Image(systemName: "lock.shield").font(.title).foregroundColor(Theme.orange)
                            VStack(alignment: .leading) {
                                Text(T("To'liq disk ruxsati kerak", "Full Disk Access needed", "Нужен полный доступ к диску")).font(.headline)
                                Text(T("Mail, Savat va konteynerlarni tozalash uchun Max Clean'ga «Full Disk Access» bering.",
                                       "Grant Max Clean Full Disk Access to clean Mail, Trash and containers.",
                                       "Дайте Max Clean полный доступ к диску, чтобы чистить Mail, Корзину и контейнеры."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(T("Ruxsat berish", "Grant access", "Разрешить")) { Permissions.openFullDiskAccess() }
                                .buttonStyle(GlowButtonStyle())
                            Button { fda = Permissions.hasFullDiskAccess } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                VStack(spacing: 8) {
                    Text(headline).font(.system(size: 32, weight: .bold, design: .rounded))
                        .id(headline)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    Text(subline).foregroundStyle(.secondary).numericTransition()
                }
                .padding(.top, 10)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: headline)
                .animation(.easeInOut, value: subline)
                .fadeIn(0)

                Group {
                    switch scan.phase {
                    case .scanning:
                        ScanProgressRing(progress: scan.progress).transition(.scale.combined(with: .opacity))
                    case .done:
                        SuccessBurst().transition(.scale.combined(with: .opacity))
                    case .results:
                        BigScanButton(title: T("Bajarish", "Run", "Выполнить"), busy: false) { confirmRun = true }
                            .disabled(!scan.canRun)
                    case .running:
                        BigScanButton(title: "", busy: true) {}
                    case .idle:
                        if junk.justCleaned {
                            SuccessBurst().transition(.scale.combined(with: .opacity))
                        } else {
                            BigScanButton(title: T("Skanerlash", "Scan", "Сканировать"), busy: false) { scan.scan() }
                        }
                    }
                }
                .frame(height: 200)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: scan.phase)
                .confirmationDialog(T("Tanlanganlar tozalansinmi? (~\(Format.bytes(scan.estimate)))",
                                      "Clean the selected items? (~\(Format.bytes(scan.estimate)))",
                                      "Очистить выбранное? (~\(Format.bytes(scan.estimate)))"),
                                    isPresented: $confirmRun) {
                    Button(T("Bajarish", "Run", "Выполнить"), role: .destructive) { scan.run() }
                } message: {
                    Text(T("Savat, eski loyiha fayllari va (yoqilgan bo'lsa) snapshotlarni qaytarib bo'lmaydi. Qolgani Savatga yoki butunlay o'chiriladi — Sozlamalarga qarab.",
                           "Trash, old project files and (if enabled) snapshots can't be restored. Other items are trashed or deleted per your Settings.",
                           "Корзину, старые файлы проектов и (если включено) снимки нельзя восстановить. Остальное — в Корзину или удаляется по настройкам."))
                }
                .fadeIn(0.05)

                if scan.phase == .results {
                    SmartScanResults(go: go)
                    Button(T("Bekor qilish", "Cancel", "Отмена")) { scan.reset() }.buttonStyle(GhostButtonStyle())
                }
                if scan.phase == .done {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(scan.notes, id: \.self) { n in
                            Label(n, systemImage: "checkmark.circle.fill").font(.callout).foregroundColor(Theme.green)
                        }
                    }
                    Button(T("Yana skanerlash", "Scan again", "Сканировать снова")) { scan.reset(); scan.scan() }
                        .buttonStyle(GhostButtonStyle())
                }

                HStack(spacing: 14) {
                    Card {
                        HStack {
                            Spacer()
                            Ring(progress: memory.diskFraction,
                                 title: T("Disk · bo'sh joy", "Disk · free", "Диск · свободно"),
                                 value: Format.bytes(memory.diskFree), size: 120, lineWidth: 10,
                                 warn: memory.diskFraction > 0.9)
                            Spacer()
                        }
                    }
                    Card {
                        HStack {
                            Spacer()
                            Ring(progress: memory.mem.fraction, title: "RAM",
                                 value: Format.mem(memory.mem.used), size: 120, lineWidth: 10,
                                 warn: memory.mem.fraction > 0.85)
                            Spacer()
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(T("Haqiqatan bo'shatildi", "Actually freed", "Реально освобождено")).foregroundStyle(.secondary)
                            Text(Format.bytes(History.totalFreed))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accentGradient)
                                .numericTransition()
                            // Savat: fayllar u yerda turgan ekan, joy bo'shamagan
                            HStack(spacing: 6) {
                                Image(systemName: "trash").foregroundColor((trashSize ?? 0) > 1_000_000_000 ? Theme.orange : .secondary)
                                Text(!fda ? T("Savat: ruxsat kerak", "Trash: needs Full Disk Access", "Корзина: нужен доступ")
                                     : trashSize.map { T("Savatda: \(Format.bytes($0))", "In Trash: \(Format.bytes($0))", "В Корзине: \(Format.bytes($0))") }
                                        ?? T("Savat hisoblanmoqda…", "Measuring Trash…", "Подсчёт Корзины…"))
                                    .font(.caption).numericTransition()
                            }
                            if let t = trashSize, t > 0 {
                                Button(emptyingTrash ? T("Bo'shatilmoqda…", "Emptying…", "Очистка…") : T("Savatni bo'shatish", "Empty Trash", "Очистить Корзину")) {
                                    confirmEmpty = true
                                }
                                .buttonStyle(GlowButtonStyle())
                                .disabled(emptyingTrash || junk.cleaning)
                            } else {
                                Button(T("RAM bo'shatish", "Free up RAM", "Освободить RAM")) { memory.freeRAM() }
                                    .buttonStyle(GhostButtonStyle())
                            }
                        }
                        .frame(height: 150)
                        .confirmationDialog(T("Savat butunlay bo'shatilsinmi?", "Empty the Trash permanently?", "Очистить Корзину навсегда?"),
                                            isPresented: $confirmEmpty) {
                            Button(T("Bo'shatish (\(Format.bytes(trashSize ?? 0)))", "Empty (\(Format.bytes(trashSize ?? 0)))",
                                     "Очистить (\(Format.bytes(trashSize ?? 0)))"), role: .destructive) { emptyTrash() }
                        } message: {
                            Text(T("Fayllarni qaytarib bo'lmaydi.", "Files can't be restored afterwards.", "Восстановить файлы будет нельзя."))
                        }
                    }
                }
                .fadeIn(0.12)

                SmartTipsCard(go: go).fadeIn(0.2)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(Array([Panel.analyzer, .large, .uninstaller, .updates, .protection, .dev, .space, .firewall].enumerated()), id: \.element) { i, p in
                        HoverTile(action: { go(p) }) {
                            VStack(spacing: 8) {
                                Image(systemName: p.icon).font(.system(size: 24)).foregroundStyle(Theme.accentGradient)
                                Text(p.title).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, 6)
                        }
                        .fadeIn(0.25 + Double(i) * 0.04)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 28)
        }
        .onAppear {
            smart.analyze(memory: memory)
            measureTrash()
        }
        .onChange(of: junk.cleaning) { cleaning in
            if !cleaning { smart.analyze(memory: memory, force: true); measureTrash(force: true) }
        }
    }
}

// MARK: - Sozlamalar

@MainActor
final class SettingsModel: ObservableObject {
    @Published var whitelist: [String] = UserDefaults.standard.stringArray(forKey: "whitelist") ?? [] {
        didSet { UserDefaults.standard.set(whitelist, forKey: "whitelist") }
    }
    @Published var log = ""
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?

    func add() {
        if let u = pickFolder(), !whitelist.contains(u.path) { whitelist.append(u.path) }
    }
    func reloadLog() { log = History.read() }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: SettingsModel
    @EnvironmentObject var smart: SmartModel
    @AppStorage("junkPermanent") private var junkPermanent = true
    @AppStorage("lang") private var lang = Lang.systemDefault.rawValue
    @AppStorage("keepInDock") private var keepInDock = false
    @AppStorage("animatedBackground") private var animatedBackground = false
    @AppStorage("menuBarPercent") private var menuBarPercent = false
    @State private var undoCount = UndoStore.count
    @State private var undoMessage: String?

    var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(icon: "gearshape", title: T("Sozlamalar", "Settings", "Настройки"),
                           subtitle: "Max Clean \(version) · Apple Silicon")
                UpdateCard()
                Card {
                    HStack {
                        Label(T("Til", "Language", "Язык"), systemImage: "globe").font(.headline)
                        Spacer()
                        Picker("", selection: $lang) {
                            ForEach(Lang.allCases) { l in Text(l.title).tag(l.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 320)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(T("Aqlli rejim", "Smart mode", "Умный режим"), systemImage: "wand.and.stars").font(.headline)
                        Toggle(T("Har hafta keshlar va loglarni avtomatik tozalash", "Auto-clean caches and logs every week",
                                 "Автоочистка кэша и логов раз в неделю"), isOn: $smart.autoClean).toggleStyle(.switch)
                        Toggle(T("Disk to'lganda ogohlantirish (10 GB dan kam)", "Warn me when the disk is almost full (under 10 GB)",
                                 "Предупреждать, когда диск почти заполнен (меньше 10 ГБ)"), isOn: $smart.lowDiskAlert).toggleStyle(.switch)
                        Toggle(T("Dock'da doim ko'rsatish (o'chiq bo'lsa — oyna yopilganda faqat menyu panelida qoladi)",
                                 "Always show in Dock (off — lives in the menu bar when the window is closed)",
                                 "Всегда показывать в Dock (выкл. — после закрытия окна остаётся в строке меню)"),
                               isOn: $keepInDock).toggleStyle(.switch)
                        Toggle(T("Harakatlanuvchi fon (ko'proq CPU/GPU ishlatadi)", "Animated background (uses more CPU/GPU)",
                                 "Анимированный фон (больше нагрузка на CPU/GPU)"),
                               isOn: $animatedBackground).toggleStyle(.switch)
                        Toggle(T("Kompyuter yoqilganda Max Clean'ni ishga tushirish", "Open Max Clean at login",
                                 "Запускать Max Clean при входе"),
                               isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                            .toggleStyle(.switch)
                        if let e = model.loginError { Text(e).font(.caption).foregroundColor(Theme.orange) }
                        Toggle(T("Fondagi og'ir jarayonlar haqida ogohlantirish (3 daqiqadan ortiq)",
                                 "Alert me about background apps hogging the CPU (3+ minutes)",
                                 "Предупреждать о фоновых процессах, нагружающих CPU (дольше 3 минут)"),
                               isOn: $smart.cpuAlerts).toggleStyle(.switch)
                        Toggle(T("Menyu panelida RAM foizini ko'rsatish", "Show RAM % in the menu bar", "Показывать % RAM в строке меню"),
                               isOn: $menuBarPercent).toggleStyle(.switch)
                            .onChange(of: menuBarPercent) { _ in AppModels.shared.statusTextChanged?() }
                        HStack {
                            Text(T("Aqlli tozalash siz qoldirgan elementlarni eslab qoladi.",
                                   "Smart Clean remembers the items you chose to keep.",
                                   "Умная очистка запоминает элементы, которые вы оставили.")).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(T("Eslab qolinganlarni tozalash", "Forget kept items", "Сбросить исключения")) { JunkModel.resetKeep() }
                                .buttonStyle(GhostButtonStyle())
                        }
                        if let a = smart.lastAuto {
                            Text(T("Oxirgi avtomatik tozalash: \(a)", "Last auto-clean: \(a)", "Последняя автоочистка: \(a)"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(T("Keshlarni darhol butunlay o'chirish (Savatga emas)", "Delete caches permanently (skip the Trash)",
                                 "Удалять кэш сразу (минуя Корзину)"), isOn: $junkPermanent)
                            .toggleStyle(.switch)
                        Text(T("Katta fayllar, dublikatlar va ilovalar har doim Savatga yuboriladi — qaytarib olish mumkin.",
                               "Large files, duplicates and apps always go to the Trash, so you can restore them.",
                               "Большие файлы, дубликаты и приложения всегда идут в Корзину — их можно вернуть."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Card {
                    HStack {
                        Text(T("To'liq disk ruxsati", "Full Disk Access", "Полный доступ к диску")).font(.headline)
                        Spacer()
                        Text(Permissions.hasFullDiskAccess ? T("Berilgan ✓", "Granted ✓", "Есть ✓") : T("Berilmagan", "Not granted", "Нет"))
                            .foregroundColor(Permissions.hasFullDiskAccess ? Theme.green : Theme.orange)
                        Button(T("Ochish", "Open", "Открыть")) { Permissions.openFullDiskAccess() }.buttonStyle(GhostButtonStyle())
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(T("Oq ro'yxat — hech qachon tegilmaydi", "Ignore list — never touched", "Исключения — никогда не трогать"))
                                .font(.headline)
                            Spacer()
                            Button(T("Papka qo'shish", "Add folder", "Добавить папку")) { model.add() }.buttonStyle(GhostButtonStyle())
                        }
                        if model.whitelist.isEmpty {
                            Text(T("Bo'sh", "Empty", "Пусто")).foregroundStyle(.secondary)
                        }
                        ForEach(model.whitelist, id: \.self) { p in
                            HStack {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                                Text(p).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button { model.whitelist.removeAll { $0 == p } } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(T("Tarix", "History", "История")).font(.headline)
                            if undoCount > 0 {
                                Button(T("Oxirgisini qaytarish (\(undoCount))", "Undo last (\(undoCount))", "Вернуть последнее (\(undoCount))")) {
                                    let n = UndoStore.restore()
                                    undoCount = UndoStore.count
                                    undoMessage = T("\(n) ta element joyiga qaytarildi", "\(n) items restored", "Восстановлено: \(n)")
                                    model.reloadLog()
                                }
                                .buttonStyle(GhostButtonStyle())
                            }
                            if let u = undoMessage { Text(u).font(.caption).foregroundColor(Theme.green) }
                            Text(T("· haqiqatan bo'shatildi: \(Format.bytes(History.totalFreed))",
                                   "· actually freed: \(Format.bytes(History.totalFreed))",
                                   "· реально освобождено: \(Format.bytes(History.totalFreed))")).foregroundStyle(.secondary)
                            Spacer()
                            Button(T("Yangilash", "Refresh", "Обновить")) { model.reloadLog() }.buttonStyle(GhostButtonStyle())
                            Button(T("Tozalash", "Clear", "Очистить")) { History.clear(); model.reloadLog() }.buttonStyle(GhostButtonStyle())
                        }
                        ScrollView {
                            Text(model.log.isEmpty ? T("Hali hech narsa o'chirilmagan", "Nothing removed yet", "Пока ничего не удалено") : model.log)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 200)
                    }
                }
            }
            .padding(24)
            .padding(.top, 12)
        }
        .onAppear { model.reloadLog() }
    }
}
