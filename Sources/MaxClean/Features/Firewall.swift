import SwiftUI
import AppKit

/// Ilovaning internetini o'chirish.
///
/// Usul: ilova macOS'ning o'z Seatbelt sandbox'i (`sandbox-exec`) ichida, tarmoq taqiqlangan profil bilan
/// ishga tushiriladi. Ilova va u ochgan barcha yordamchi jarayonlar internetga chiqa olmaydi, lokal
/// IPC (unix socket) esa ishlayveradi. Apple Developer hisobi yoki tizim kengaytmasi kerak emas.
/// Max Clean ochiq turganda bloklangan ilova oddiy usulda ochilsa, u avtomatik yopilib, internetsiz qayta ochiladi.
enum OfflineLauncher {
    static let profile = """
    (version 1)
    (allow default)
    (deny network-outbound (remote ip "*:*"))
    (allow network-outbound (remote ip "localhost:*"))
    (deny network-inbound (local ip "*:*"))
    (allow network-inbound (local ip "localhost:*"))
    """

    static func executable(of app: URL) -> URL? {
        Bundle(url: app)?.executableURL
    }

    /// Ilovani internetsiz ishga tushiradi va PID qaytaradi.
    @discardableResult
    static func launch(_ app: URL) -> Int32? {
        guard let exe = executable(of: app) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        p.arguments = ["-p", profile, exe.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.currentDirectoryURL = FS.home
        do { try p.run() } catch { return nil }
        History.add("FIREWALL\t\(app.path)")
        return p.processIdentifier
    }
}

struct BlockedApp: Identifiable, Hashable, Codable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String
}

@MainActor
final class FirewallModel: ObservableObject {
    @Published var blocked: [BlockedApp] = [] { didSet { save() } }
    @Published var apps: [AppInfo] = []
    @Published var search = ""
    @Published var message: String?
    @Published var autoEnforce: Bool = UserDefaults.standard.object(forKey: "fwAuto") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoEnforce, forKey: "fwAuto") }
    }

    /// Biz internetsiz ochgan jarayonlar (ularni qayta tutmaslik uchun).
    private var ourPIDs = Set<Int32>()
    private var observer: NSObjectProtocol?

    init() {
        if let d = UserDefaults.standard.data(forKey: "fwBlocked"),
           let list = try? JSONDecoder().decode([BlockedApp].self, from: d) {
            blocked = list
        }
        startWatching()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(blocked) { UserDefaults.standard.set(d, forKey: "fwBlocked") }
    }

    var visibleApps: [AppInfo] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    func loadApps() {
        guard apps.isEmpty else { return }
        Task {
            self.apps = await Task.detached { AppScanner.installedApps() }.value
        }
    }

    func isBlocked(_ app: AppInfo) -> Bool { blocked.contains { $0.path == app.url.path } }

    func setBlocked(_ app: AppInfo, _ on: Bool) {
        if on {
            guard !isBlocked(app) else { return }
            blocked.append(BlockedApp(path: app.url.path, name: app.name, bundleID: app.bundleID))
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
            message = running.isEmpty
                ? T("\(app.name) endi internetsiz ochiladi.",
                    "\(app.name) will now open without internet.",
                    "\(app.name) теперь будет открываться без интернета.")
                : T("\(app.name) hozir ochiq — internetsiz ishlashi uchun «Qayta ochish»ni bosing.",
                    "\(app.name) is running — press Relaunch to cut its internet.",
                    "\(app.name) запущено — нажмите «Перезапустить», чтобы отключить интернет.")
        } else {
            blocked.removeAll { $0.path == app.url.path }
            message = T("\(app.name) uchun internet yoqildi (ilovani qayta oching).",
                        "Internet allowed for \(app.name) (relaunch the app).",
                        "Интернет для \(app.name) разрешён (перезапустите приложение).")
        }
    }

    func relaunchOffline(_ app: AppInfo) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
            .filter { !ourPIDs.contains($0.processIdentifier) }
        running.forEach { $0.terminate() }
        Task {
            // Ilova yopilishini kutamiz (ko'pi bilan ~5 s)
            for _ in 0..<25 where running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if running.contains(where: { !$0.isTerminated }) {
                // Majburan yopmaymiz — saqlanmagan ish yo'qolmasin
                self.message = T("\(app.name) yopilmadi — ishingizni saqlab, o'zingiz yoping va qayta urinib ko'ring.",
                                 "\(app.name) didn't quit — save your work, quit it and try again.",
                                 "\(app.name) не закрылось — сохраните работу, закройте его и попробуйте снова.")
                return
            }
            if let pid = OfflineLauncher.launch(app.url) {
                self.ourPIDs.insert(pid)
                self.message = T("\(app.name) internetsiz ochildi.", "\(app.name) opened offline.", "\(app.name) открыто без интернета.")
            } else {
                self.message = T("Ochib bo'lmadi.", "Couldn't launch.", "Не удалось запустить.")
            }
        }
    }

    private func startWatching() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.handleLaunch(app) }
        }
    }

    private func handleLaunch(_ app: NSRunningApplication) {
        guard autoEnforce, let url = app.bundleURL,
              blocked.contains(where: { $0.path == url.path }) else { return }
        // O'zimiz ochgan nusxa yoki uning jarayonlari — tegmaymiz
        if ourPIDs.contains(app.processIdentifier) { return }
        if isSandboxedByUs(app.processIdentifier) { ourPIDs.insert(app.processIdentifier); return }
        let info = AppScanner.info(url)
        relaunchOffline(info)
    }

    /// sandbox-exec "exec" qiladi, shuning uchun PID o'zgarmaydi; ota jarayon sifatida ham tekshiramiz.
    private func isSandboxedByUs(_ pid: Int32) -> Bool {
        let out = Shell.run("/bin/ps", ["-o", "ppid=", "-p", String(pid)]).out.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ppid = Int32(out), ourPIDs.contains(ppid) { return true }
        return false
    }
}

struct FirewallView: View {
    @EnvironmentObject var model: FirewallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "network.slash",
                       title: T("Internet blokirovkasi", "App Firewall", "Блокировка интернета"),
                       subtitle: T("Tanlangan ilovalar internetga chiqa olmaydi — litsenziya tekshiruvi, reklama va telemetriya to'xtaydi",
                                   "Chosen apps can't reach the internet — no phoning home, ads or telemetry",
                                   "Выбранные приложения не выходят в интернет — без телеметрии, рекламы и проверок")) {
                Toggle(T("Avtomatik", "Auto-enforce", "Автоматически"), isOn: $model.autoEnforce)
                    .toggleStyle(.switch)
                    .help(T("Max Clean ochiq turganda bloklangan ilova oddiy ochilsa, internetsiz qayta ochiladi",
                            "While Max Clean runs, blocked apps opened normally are relaunched offline",
                            "Пока Max Clean запущен, заблокированные приложения перезапускаются без интернета"))
            }
            if let m = model.message {
                Label(m, systemImage: "info.circle.fill").foregroundColor(Theme.green)
            }
            HStack(alignment: .top, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(T("Bloklangan", "Blocked", "Заблокировано")).font(.headline)
                        if model.blocked.isEmpty {
                            Text(T("Hozircha yo'q. O'ngdan ilovani tanlang.",
                                   "None yet. Pick an app on the right.",
                                   "Пока пусто. Выберите приложение справа."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(model.blocked) { b in
                            HStack {
                                Image(nsImage: IconCache.icon(b.path)).resizable().frame(width: 26, height: 26)
                                VStack(alignment: .leading) {
                                    Text(b.name)
                                    Label(T("Internet o'chiq", "Offline", "Без интернета"), systemImage: "wifi.slash")
                                        .font(.caption).foregroundColor(Theme.orange)
                                }
                                Spacer()
                                let info = AppScanner.info(URL(fileURLWithPath: b.path))
                                Button(T("Qayta ochish", "Relaunch", "Перезапустить")) { model.relaunchOffline(info) }
                                    .buttonStyle(GhostButtonStyle())
                                Button { model.setBlocked(info, false) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless)
                                    .help(T("Internetni qaytarish", "Allow internet", "Разрешить интернет"))
                            }
                            .padding(.vertical, 4)
                        }
                        Spacer(minLength: 0)
                        Divider().opacity(0.3)
                        Text(T("Eslatma: App Store ilovalari va o'z sandbox'iga ega ba'zi ilovalar bu usulda ochilmasligi mumkin. Tizim xizmatlari (masalan, iCloud) orqali ketadigan trafik bloklanmaydi.",
                               "Note: some App Store / self-sandboxed apps may refuse to start this way. Traffic sent through system services (e.g. iCloud) isn't blocked.",
                               "Примечание: некоторые приложения из App Store и с собственной песочницей могут не запуститься так. Трафик через системные службы (например, iCloud) не блокируется."))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 380)

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(T("Ilova qidirish", "Search apps", "Поиск приложений"), text: $model.search)
                            .textFieldStyle(.roundedBorder)
                        List(model.visibleApps, id: \.id) { app in
                            HStack {
                                Image(nsImage: IconCache.icon(app.url.path)).resizable().frame(width: 24, height: 24)
                                Text(app.name).lineLimit(1)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { model.isBlocked(app) },
                                    set: { model.setBlocked(app, $0) }))
                                    .toggleStyle(.switch).labelsHidden()
                                    .help(T("Internetni o'chirish", "Block internet", "Заблокировать интернет"))
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
        .padding(24)
        .onAppear { model.loadApps() }
    }
}
