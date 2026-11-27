import SwiftUI
import AppKit
import Combine

/// Barcha modellar bitta joyda — asosiy oyna ham, menyu paneli ham bir xil holatni ko'radi.
@MainActor
final class AppModels: ObservableObject {
    static let shared = AppModels()

    let junk = JunkModel()
    let memory = MemoryModel()
    let large = LargeFilesModel()
    let dups = DuplicatesModel()
    let dev = DevModel()
    let uninstaller = UninstallerModel()
    let startup = StartupModel()
    let maintenance = MaintenanceModel()
    let space = SpaceModel()
    let settings = SettingsModel()
    let firewall = FirewallModel()
    let smart = SmartModel()
    let updates = UpdatesModel()
    let protection = ProtectionModel()
    let updater = AutoUpdater()
    let disk = DiskAnalyzerModel()
    let smartScan = SmartScanModel()
    let browsers = BrowsersModel()
    /// Menyu panelidagi matnni yangilash (sozlama o'zgarganda)
    var statusTextChanged: (() -> Void)?

    /// Menyu panelidan asosiy oynadagi bo'limni ochish uchun.
    @Published var requestedPanel: Panel?
    /// SwiftUI'ning openWindow amali (asosiy oyna yopilgandan keyin qayta ochish uchun).
    var openMain: (() -> Void)?

    static func isMainWindow(_ w: NSWindow) -> Bool {
        w.identifier?.rawValue.hasPrefix("main") == true
    }

    var keepInDock: Bool { UserDefaults.standard.bool(forKey: "keepInDock") }

    func showMain(panel: Panel? = nil) {
        NSApp.setActivationPolicy(.regular)
        if let w = NSApp.windows.first(where: { AppModels.isMainWindow($0) && ($0.isVisible || $0.isMiniaturized) }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            openMain?()
        }
        NSApp.activate(ignoringOtherApps: true)
        if let panel { requestedPanel = panel }
    }

    /// Asosiy oyna yopilganda — Dock'dan yo'qolib, faqat menyu panelida qoladi.
    func mainWindowClosed() {
        guard !keepInDock else { return }
        // Boshqa ko'rinib turgan asosiy oyna bo'lmasa
        let others = NSApp.windows.filter { AppModels.isMainWindow($0) && $0.isVisible }
        if others.count <= 1 { NSApp.setActivationPolicy(.accessory) }
    }
}

// MARK: - App delegate: menyu paneli belgisi + Dock xatti-harakati

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var lastClose = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let m = AppModels.shared
        m.smart.startBackground()
        m.updater.startBackground()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = item.button {
            let img = NSImage(systemSymbolName: "display", accessibilityDescription: "Max Clean")
            img?.isTemplate = true
            b.image = img
            b.target = self
            b.action = #selector(togglePopover(_:))
            // Chap va o'ng tugma — ikkalasi ham panelni ochadi
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        // Ixtiyoriy: belgi yonida RAM foizi
        m.statusTextChanged = { [weak self] in self?.updateStatusText() }
        m.memory.$mem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mem in self?.updateStatusText(mem.fraction) }
            .store(in: &cancellables)

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let hc = NSHostingController(rootView: MenuBarRoot(close: { [weak self] in
            self?.popover.performClose(nil)
        }))
        hc.sizingOptions = .preferredContentSize
        popover.contentViewController = hc

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let obj = note.object
            Task { @MainActor in
                guard let w = obj as? NSWindow, AppModels.isMainWindow(w) else { return }
                AppModels.shared.mainWindowClosed()
            }
        })
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            let obj = note.object
            Task { @MainActor in
                guard let w = obj as? NSWindow, AppModels.isMainWindow(w) else { return }
                if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
            }
        })
    }

    func popoverDidClose(_ notification: Notification) { lastClose = Date() }

    private func updateStatusText(_ fraction: Double? = nil) {
        guard let item = statusItem, let b = item.button else { return }
        if UserDefaults.standard.bool(forKey: "menuBarPercent") {
            let pct = Int(((fraction ?? AppModels.shared.memory.mem.fraction) * 100).rounded())
            item.length = NSStatusItem.variableLength
            b.imagePosition = .imageLeading
            b.attributedTitle = NSAttributedString(
                string: " \(pct)%",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)])
        } else {
            if item.length == NSStatusItem.squareLength && b.title.isEmpty { return }
            b.title = ""
            b.imagePosition = .imageOnly
            item.length = NSStatusItem.squareLength
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(sender); return }
        // Belgini bosib yopganda darhol qayta ochilib ketmasligi uchun
        guard Date().timeIntervalSince(lastClose) > 0.3 else { return }
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        let m = AppModels.shared
        if m.openMain != nil { m.showMain(); return false } // o'zimiz ochdik
        NSApp.setActivationPolicy(.regular)
        return true // SwiftUI oynani yaratsin
    }
}

// MARK: - Menyu paneli (popover)

struct MenuBarRoot: View {
    let close: () -> Void
    @AppStorage("lang") private var lang = Lang.systemDefault.rawValue

    var body: some View {
        MenuBarPanel(close: close)
            .environmentObject(AppModels.shared.memory)
            .environmentObject(AppModels.shared.junk)
            .environmentObject(AppModels.shared.smart)
            .environmentObject(AppModels.shared.updater)
            .id(lang)
            .preferredColorScheme(.dark)
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var updater: AutoUpdater
    @EnvironmentObject var memory: MemoryModel
    @EnvironmentObject var junk: JunkModel
    @EnvironmentObject var smart: SmartModel
    let close: () -> Void

    private func open(_ p: Panel?) {
        close()
        AppModels.shared.showMain(panel: p)
    }

    var body: some View {
        ZStack {
            AnimatedBackground(compact: true)
            VStack(alignment: .leading, spacing: 12) {
                // Sarlavha
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Max Clean").font(.system(size: 16, weight: .heavy, design: .rounded))
                        Text(T("Mac holati", "Mac status", "Состояние Mac")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HealthBadge(score: smart.score, busy: smart.analyzing)
                }
                .fadeIn(0)

                // Halqalar
                HStack(spacing: 10) {
                    MiniStat {
                        Ring(progress: memory.diskFraction, title: T("Bo'sh disk", "Free disk", "Свободно"),
                             value: Format.bytes(memory.diskFree), size: 92, lineWidth: 8,
                             warn: memory.diskFraction > 0.9)
                    }
                    MiniStat {
                        Ring(progress: memory.mem.fraction, title: "RAM",
                             value: Format.mem(memory.mem.used), size: 92, lineWidth: 8,
                             warn: memory.mem.fraction > 0.85)
                    }
                }
                .fadeIn(0.05)

                // CPU
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(T("CPU yuklama", "CPU load", "Нагрузка CPU"), systemImage: "cpu").font(.caption)
                        Spacer()
                        Text(String(format: "%.1f", memory.loadAvg)).font(.caption.weight(.semibold)).numericTransition()
                    }
                    SizeBar(fraction: memory.cpuFraction).animation(.easeInOut(duration: 0.6), value: memory.cpuFraction)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .fadeIn(0.1)

                // Tozalash
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.accentGradient).frame(width: 40, height: 40)
                            .shadow(color: Theme.accent.opacity(0.6), radius: 8)
                        if junk.scanning || junk.cleaning {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: junk.scannedOnce ? "trash" : "sparkle.magnifyingglass")
                                .foregroundColor(.white)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(junkTitle).font(.subheadline.weight(.semibold)).numericTransition()
                        Text(junkSubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(junk.scannedOnce && junk.selectedSize > 0 ? T("Tozalash", "Clean", "Очистить") : T("Skanerlash", "Scan", "Сканировать")) {
                        if junk.scannedOnce && junk.selectedSize > 0 { junk.clean() } else { junk.scan() }
                    }
                    .buttonStyle(GlowButtonStyle())
                    .disabled(junk.scanning || junk.cleaning)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .fadeIn(0.15)

                // Yangi versiya chiqqan bo'lsa
                if case .available(let v) = updater.state {
                    Button { open(.settings) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.circle.fill").foregroundColor(Theme.green)
                            Text(T("Max Clean \(v) chiqdi — yangilash", "Max Clean \(v) is out — update",
                                   "Вышел Max Clean \(v) — обновить")).font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.green.opacity(0.12)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Eng muhim maslahat
                if let tip = smart.tips.first {
                    Button { open(tip.panel) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tip.icon)
                                .foregroundColor(tip.level == .critical ? Theme.red : tip.level == .warn ? Theme.orange : Theme.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tip.title).font(.caption.weight(.semibold))
                                Text(tip.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fadeIn(0.2)
                }

                // Tezkor amallar
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    QuickAction(icon: "memorychip", title: T("RAM bo'shatish", "Free RAM", "Освободить RAM")) {
                        close(); memory.freeRAM()
                    }
                    QuickAction(icon: "xmark.app", title: T("Ilovalar", "Uninstaller", "Приложения")) { open(.uninstaller) }
                    QuickAction(icon: "network.slash", title: T("Firewall", "Firewall", "Firewall")) { open(.firewall) }
                    QuickAction(icon: "circle.hexagongrid", title: T("Disk xaritasi", "Disk Map", "Карта диска")) { open(.space) }
                }
                .fadeIn(0.25)

                HStack {
                    Button { open(.dashboard) } label: {
                        Label(T("Max Clean'ni ochish", "Open Max Clean", "Открыть Max Clean"), systemImage: "macwindow")
                    }
                    .buttonStyle(GhostButtonStyle())
                    Spacer()
                    Button { open(.settings) } label: { Image(systemName: "gearshape") }
                        .buttonStyle(GhostButtonStyle())
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                        .buttonStyle(GhostButtonStyle())
                        .help(T("Chiqish", "Quit", "Выход"))
                }
                .fadeIn(0.3)
            }
            .padding(16)
        }
        .frame(width: 350)
        .onAppear { smart.analyze(memory: memory) }
    }

    var junkTitle: String {
        if junk.scanning { return T("Skanerlanmoqda… \(Int(junk.progress * 100))%", "Scanning… \(Int(junk.progress * 100))%", "Сканирование… \(Int(junk.progress * 100))%") }
        if junk.cleaning { return T("Tozalanmoqda…", "Cleaning…", "Очистка…") }
        if junk.scannedOnce { return T("\(Format.bytes(junk.total)) keraksiz", "\(Format.bytes(junk.total)) of junk", "\(Format.bytes(junk.total)) мусора") }
        return T("Tezkor tozalash", "Quick clean", "Быстрая очистка")
    }

    var junkSubtitle: String {
        if junk.lastFreed > 0 {
            return T("Oxirgi: \(Format.bytes(junk.lastFreed)) bo'shatildi", "Last: \(Format.bytes(junk.lastFreed)) freed",
                     "Последняя: освобождено \(Format.bytes(junk.lastFreed))")
        }
        return T("Kesh, log, Claude va Xcode", "Caches, logs, Claude & Xcode", "Кэш, логи, Claude и Xcode")
    }
}

struct MiniStat<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        HStack { Spacer(); content; Spacer() }
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }
}

struct QuickAction: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(Theme.accentGradient).frame(width: 18)
                Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Theme.cardHover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hover ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
            .scaleEffect(hover ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct HealthBadge: View {
    let score: Int
    let busy: Bool
    var color: Color { score >= 80 ? Theme.green : score >= 50 ? Theme.orange : Theme.red }
    var body: some View {
        HStack(spacing: 5) {
            if busy {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(score)").font(.caption.weight(.bold)).numericTransition()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.18)))
        .foregroundColor(color)
        .animation(.spring(), value: score)
    }
}
