import SwiftUI
import AppKit

// MARK: - Himoya: adware, imzosiz agentlar, shubhali kengaytmalar
//
// Antivirus bazasi emas — macOS'da reklama dasturlari va "keraksiz" dasturlar odatda
// fon agentlari (LaunchAgents/Daemons) va brauzer kengaytmalari orqali yashaydi.
// Biz shularni tekshiramiz: ma'lum adware nomlari, imzosiz yoki buzilgan dasturlar,
// mavjud bo'lmagan faylga ishora qiluvchi "o'lik" agentlar.

struct Finding: Identifiable, Sendable {
    enum Level: Int, Sendable { case info = 0, warn = 1, danger = 2 }
    enum Kind: Sendable { case launchItem(LaunchItem), extensionDir(URL), app(URL) }
    let id = UUID()
    let title: String
    let detail: String
    let path: String
    let level: Level
    let kind: Kind
}

enum Protector {
    /// Mashhur Mac adware/PUP oilalari (nom yoki yo'lda uchrasa — xavfli).
    static let adwarePatterns = [
        "mackeeper", "advancedmaccleaner", "advanced mac cleaner", "macautofixer", "mac auto fixer",
        "searchmine", "searchbaron", "searchmarquis", "searchpulse", "shlayer", "bundlore", "pirrit",
        "genieo", "vsearch", "adload", "mykotlerino", "chumsearch", "safefinder", "weknow", "spigot",
        "installmac", "smartsearch", "macsearch", "conduit", "crossrider", "geonei", "tarmac"
    ]

    struct Signature: Sendable {
        let signed: Bool
        let valid: Bool
        let authority: String?
    }

    static func signature(_ path: String) -> Signature {
        let info = Shell.run("/usr/bin/codesign", ["-dv", "--verbose=2", path])
        if info.out.contains("not signed at all") { return Signature(signed: false, valid: false, authority: nil) }
        let authority = info.out.split(separator: "\n")
            .first { $0.hasPrefix("Authority=") }
            .map { String($0.dropFirst("Authority=".count)) }
        let verify = Shell.run("/usr/bin/codesign", ["--verify", path])
        return Signature(signed: true, valid: verify.status == 0, authority: authority)
    }

    static func matchesAdware(_ s: String) -> Bool {
        let l = s.lowercased()
        return adwarePatterns.contains { l.contains($0) }
    }

    static func scan() -> [Finding] {
        var out: [Finding] = []

        // 1) Fon agentlari va daemonlar
        for item in LaunchScanner.load() {
            let prog = item.program
            if matchesAdware(item.label) || matchesAdware(prog) || matchesAdware(item.path) {
                out.append(Finding(title: item.label,
                                   detail: T("Ma'lum reklama/keraksiz dasturga o'xshaydi", "Matches known adware / unwanted software",
                                             "Похоже на известное рекламное/нежелательное ПО"),
                                   path: item.path, level: .danger, kind: .launchItem(item)))
                continue
            }
            guard prog != "—", prog.hasPrefix("/") else { continue }
            // Tashqi diskdagi (masalan T9) dastur — disk ulanmagan bo'lishi mumkin, "o'lik" demaymiz
            if prog.hasPrefix("/Volumes/") { continue }
            if !FS.fm.fileExists(atPath: prog) {
                out.append(Finding(title: item.label,
                                   detail: T("Dasturi o'chirilgan — o'lik agent, olib tashlash xavfsiz",
                                             "Its program is gone — a dead agent, safe to remove",
                                             "Программа удалена — «мёртвый» агент, можно удалить"),
                                   path: item.path, level: .warn, kind: .launchItem(item)))
                continue
            }
            if prog.hasPrefix("/System/") || prog.hasPrefix("/usr/") { continue }
            let sig = signature(prog)
            if !sig.signed {
                out.append(Finding(title: item.label,
                                   detail: T("Imzosiz dastur fonda ishlaydi: \(prog)", "Unsigned program runs in the background: \(prog)",
                                             "Неподписанная программа работает в фоне: \(prog)"),
                                   path: item.path, level: .warn, kind: .launchItem(item)))
            } else if !sig.valid {
                out.append(Finding(title: item.label,
                                   detail: T("Imzo buzilgan (fayl o'zgartirilgan bo'lishi mumkin): \(prog)",
                                             "Broken signature (the file may have been modified): \(prog)",
                                             "Подпись нарушена (файл мог быть изменён): \(prog)"),
                                   path: item.path, level: .warn, kind: .launchItem(item)))
            }
        }

        // 2) Chrome / Edge / Brave kengaytmalari
        let browsers = ["Google/Chrome", "Microsoft Edge", "BraveSoftware/Brave-Browser"]
        for b in browsers {
            let root = FS.home.appendingPathComponent("Library/Application Support/\(b)")
            guard FS.exists(root) else { continue }
            let profiles = FS.children(root).filter {
                $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ")
            }
            for profile in profiles {
                for ext in FS.children(profile.appendingPathComponent("Extensions")) where FS.isDir(ext) {
                    guard let ver = FS.children(ext).filter({ FS.isDir($0) }).first,
                          let data = try? Data(contentsOf: ver.appendingPathComponent("manifest.json")),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let name = (json["name"] as? String) ?? ext.lastPathComponent
                    let perms = ((json["permissions"] as? [Any]) ?? []).compactMap { $0 as? String }
                        + ((json["host_permissions"] as? [Any]) ?? []).compactMap { $0 as? String }
                    let browserName = b.components(separatedBy: "/").last ?? b
                    if matchesAdware(name) || matchesAdware(json["description"] as? String ?? "") {
                        out.append(Finding(title: "\(browserName): \(name)",
                                           detail: T("Ma'lum reklama kengaytmasiga o'xshaydi", "Matches known adware extension",
                                                     "Похоже на известное рекламное расширение"),
                                           path: ext.path, level: .danger, kind: .extensionDir(ext)))
                    } else if perms.contains("<all_urls>") || perms.contains("*://*/*") {
                        let shown = name.hasPrefix("__MSG_") ? ext.lastPathComponent : name
                        out.append(Finding(title: "\(browserName): \(shown)",
                                           detail: T("Barcha saytlardagi ma'lumotlarni o'qiy oladi — tanish bo'lmasa, o'chiring",
                                                     "Can read data on every website — remove it if you don't recognize it",
                                                     "Может читать данные на всех сайтах — удалите, если не узнаёте"),
                                           path: ext.path, level: .info, kind: .extensionDir(ext)))
                    }
                }
            }
        }

        // 3) Ilovalar: adware nomlari va imzosiz ilovalar
        for app in AppScanner.installedApps() {
            if matchesAdware(app.name) || matchesAdware(app.bundleID) {
                out.append(Finding(title: app.name,
                                   detail: T("Ma'lum keraksiz dastur", "Known unwanted software", "Известное нежелательное ПО"),
                                   path: app.url.path, level: .danger, kind: .app(app.url)))
            } else if !signature(app.url.path).signed {
                out.append(Finding(title: app.name,
                                   detail: T("Imzosiz ilova — manbasini bilsangiz, xavotir yo'q",
                                             "Unsigned app — fine if you trust where it came from",
                                             "Неподписанное приложение — нормально, если вы доверяете источнику"),
                                   path: app.url.path, level: .info, kind: .app(app.url)))
            }
        }

        return out.sorted { $0.level.rawValue > $1.level.rawValue }
    }
}

@MainActor
final class ProtectionModel: ObservableObject {
    @Published var findings: [Finding] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var message: String?

    var dangerCount: Int { findings.filter { $0.level == .danger }.count }

    func scan() {
        guard !scanning else { return }
        scanning = true
        message = nil
        Task {
            let f = await Task.detached(priority: .userInitiated) { Protector.scan() }.value
            self.findings = f
            self.scanning = false
            self.scanned = true
        }
    }

    func remove(_ f: Finding) {
        switch f.kind {
        case .launchItem(let item):
            AppModels.shared.startup.remove(item)
            message = AppModels.shared.startup.message
            if !FS.fm.fileExists(atPath: f.path) { findings.removeAll { $0.id == f.id } }
        case .extensionDir(let url):
            // Papkani o'chirish yetarli emas (brauzer qayta tiklaydi) — brauzerning o'z sahifasini ochamiz
            let id = url.lastPathComponent
            let bid = url.path.contains("Microsoft Edge") ? "com.microsoft.edgemac"
                : url.path.contains("BraveSoftware") ? "com.brave.Browser" : "com.google.Chrome"
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid),
               let u = URL(string: "chrome://extensions/?id=\(id)") {
                NSWorkspace.shared.open([u], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
            message = T("Brauzerda ochilgan sahifada «Olib tashlash»ni bosing.", "Click Remove on the page that opened in the browser.",
                        "Нажмите «Удалить» на открывшейся странице браузера.")
        case .app(let url):
            let title = f.title
            Task {
                let r = await Task.detached {
                    Remover.remove([FileEntry(url: url, size: FS.allocatedSize(of: url), modified: nil, selected: true)],
                                   permanently: false)
                }.value
                if r.failed.isEmpty {
                    self.message = T("\(title) Savatga yuborildi.", "\(title) moved to Trash.", "\(title) перемещено в Корзину.")
                    self.findings.removeAll { $0.id == f.id }
                } else {
                    self.message = T("O'chirib bo'lmadi — ilova ochiq bo'lishi mumkin.", "Couldn't remove — it may be running.",
                                     "Не удалось удалить — возможно, запущено.")
                }
            }
        }
    }
}

struct ProtectionView: View {
    @EnvironmentObject var model: ProtectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(icon: "checkmark.shield",
                       title: T("Himoya", "Protection", "Защита"),
                       subtitle: T("Reklama dasturlari, imzosiz fon agentlari va shubhali brauzer kengaytmalari",
                                   "Adware, unsigned background agents and suspicious browser extensions",
                                   "Рекламное ПО, неподписанные фоновые агенты и подозрительные расширения")) {
                Button(model.scanning ? T("Tekshirilmoqda…", "Scanning…", "Проверка…") : T("Tekshirish", "Scan", "Проверить")) {
                    model.scan()
                }
                .buttonStyle(GlowButtonStyle()).disabled(model.scanning)
            }
            if let m = model.message { Label(m, systemImage: "info.circle.fill").foregroundColor(Theme.green) }

            if model.scanning {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView().controlSize(.large)
                    Text(T("Agentlar, ilovalar va kengaytmalar tekshirilmoqda…", "Checking agents, apps and extensions…",
                           "Проверка агентов, приложений и расширений…")).foregroundStyle(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else if !model.scanned {
                EmptyState(icon: "checkmark.shield", text: T("«Tekshirish»ni bosing", "Press Scan", "Нажмите «Проверить»"))
            } else if model.findings.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    SuccessBurst()
                    Text(T("Hech qanday xavf topilmadi", "No threats found", "Угроз не найдено")).font(.title3.bold())
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                if model.dangerCount > 0 {
                    Label(T("\(model.dangerCount) ta xavfli element topildi", "\(model.dangerCount) dangerous items found",
                            "Найдено опасных элементов: \(model.dangerCount)"), systemImage: "exclamationmark.octagon.fill")
                        .foregroundColor(Theme.red).font(.headline)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(model.findings.enumerated()), id: \.element.id) { i, f in
                            Card(padding: 12) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(color(f.level).opacity(0.18)).frame(width: 34, height: 34)
                                        Image(systemName: icon(f.level)).foregroundColor(color(f.level))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(f.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    Button { FS.reveal(URL(fileURLWithPath: f.path)) } label: { Image(systemName: "magnifyingglass") }
                                        .buttonStyle(.borderless)
                                    Button(T("Olib tashlash", "Remove", "Удалить")) { model.remove(f) }
                                        .buttonStyle(GhostButtonStyle())
                                }
                            }
                            .fadeIn(Double(min(i, 10)) * 0.03)
                        }
                    }
                }
            }
        }
        .padding(24)
    }

    func color(_ l: Finding.Level) -> Color {
        switch l {
        case .danger: return Theme.red
        case .warn: return Theme.orange
        case .info: return Theme.accent
        }
    }

    func icon(_ l: Finding.Level) -> String {
        switch l {
        case .danger: return "exclamationmark.octagon.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}
