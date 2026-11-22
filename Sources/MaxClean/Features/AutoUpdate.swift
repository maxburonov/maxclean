import SwiftUI
import AppKit

// MARK: - Avtomatik yangilanish (GitHub Releases)
//
// 1) https://api.github.com/repos/<repo>/releases/latest dan oxirgi versiyani olamiz
// 2) Yangi bo'lsa — DMG'ni yuklab olamiz, hdiutil bilan ochib, "Max Clean.app"ni vaqtinchalik joyga nusxalaymiz
// 3) Kichik skript ilova yopilishini kutadi, eski ilovani yangisi bilan almashtiradi va qayta ochadi.
//    Xatolik bo'lsa eski versiya joyiga qaytariladi.

enum UpdateConfig {
    /// Info.plist → MaxUpdateRepo (masalan "maxburonov/maxclean")
    static var repo: String {
        (Bundle.main.object(forInfoDictionaryKey: "MaxUpdateRepo") as? String) ?? "maxburonov/maxclean"
    }
    static var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
    static var workDir: URL {
        FS.home.appendingPathComponent("Library/Caches/uz.max.clean/Update", isDirectory: true)
    }
}

struct ReleaseInfo: Sendable {
    let version: String
    let notes: String
    let dmgURL: URL
    let size: Int64
    let page: URL?
}

enum ReleaseFetcher {
    enum FetchError: Error { case http(Int), noDMG, bad }

    static func latest() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(UpdateConfig.repo)/releases/latest") else { throw FetchError.bad }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MaxClean/\(UpdateConfig.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw FetchError.http(code) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw FetchError.bad }
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        guard let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let s = dmg["browser_download_url"] as? String, let dl = URL(string: s) else { throw FetchError.noDMG }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return ReleaseInfo(version: version,
                           notes: (json["body"] as? String) ?? "",
                           dmgURL: dl,
                           size: (dmg["size"] as? NSNumber)?.int64Value ?? 0,
                           page: (json["html_url"] as? String).flatMap(URL.init(string:)))
    }
}

/// Yuklab olish progressi bilan (URLSessionDownloadDelegate).
final class DownloadTask: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Double) -> Void
    private let destination: URL

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func run(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
            self.continuation = c
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            continuation?.resume(throwing: ReleaseFetcher.FetchError.http(http.statusCode))
            continuation = nil
            session.finishTasksAndInvalidate()
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
            session.finishTasksAndInvalidate()
        }
    }
}

enum Installer {
    enum InstallError: Error { case mount(String), notFound, wrongApp, notWritable, translocated }

    /// Ilova yangilanishi mumkin bo'lgan joydami? (DMG ichidan yoki "translocation"dan ishlayotgan bo'lsa — yo'q)
    static func canSelfUpdate() -> Bool {
        let url = Bundle.main.bundleURL
        if url.path.contains("/AppTranslocation/") { return false }
        // DMG kabi faqat-o'qish disklari — yo'q; T9 kabi tashqi disk — mumkin
        if let ro = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly, ro { return false }
        return FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    /// DMG'ni ochib, ichidagi ilovani vaqtinchalik joyga nusxalaydi. Tayyor ilova yo'lini qaytaradi.
    static func stage(dmg: URL, expectedVersion: String) throws -> URL {
        let fm = FileManager.default
        let mount = UpdateConfig.workDir.appendingPathComponent("mnt", isDirectory: true)
        let staged = UpdateConfig.workDir.appendingPathComponent("Max Clean.app", isDirectory: true)
        try? fm.removeItem(at: staged)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
        let r = Shell.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                                "-mountpoint", mount.path, "-quiet"])
        guard r.status == 0 else { throw InstallError.mount(r.out) }
        defer { Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"]) }
        guard let app = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" }) else { throw InstallError.notFound }
        // Xavfsizlik: aynan Max Clean ekanini va versiyasini tekshiramiz
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
        guard let info, info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == expectedVersion
        else { throw InstallError.wrongApp }
        let c = Shell.run("/usr/bin/ditto", [app.path, staged.path])
        guard c.status == 0 else { throw InstallError.mount(c.out) }
        return staged
    }

    /// Ilova yopilgach almashtiruvchi skriptni ishga tushiradi va ilovani yopadi.
    @MainActor
    static func replaceAndRelaunch(with staged: URL) throws {
        let target = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let q = Shell.quote
        // Xavfsiz almashtirish: eski ilova o'chirilmasdan oldin zaxiraga ko'chiriladi;
        // ko'chirib bo'lmasa — hech narsa o'chirilmaydi, eski ilova qayta ochiladi.
        let script = """
        #!/bin/sh
        T=\(q(target))
        S=\(q(staged.path))
        B="$T.old-$$"
        i=0
        while kill -0 \(pid) 2>/dev/null; do
          sleep 0.3; i=$((i+1))
          [ $i -gt 400 ] && exit 0
        done
        if ! mv "$T" "$B"; then
          /usr/bin/open "$T"; exit 1
        fi
        if /usr/bin/ditto "$S" "$T"; then
          rm -rf "$B"
        else
          rm -rf "$T"; mv "$B" "$T"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$T" 2>/dev/null
        rm -rf "$S"
        /usr/bin/open "$T"
        """
        let scriptURL = UpdateConfig.workDir.appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [scriptURL.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        History.add("YANGILANISH\t\(UpdateConfig.currentVersion) → \(staged.path)")
        NSApp.terminate(nil)
    }
}

@MainActor
final class AutoUpdater: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(String)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var release: ReleaseInfo?
    @Published var autoCheck: Bool = UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "autoUpdateCheck") }
    }
    @Published var autoInstall: Bool = UserDefaults.standard.bool(forKey: "autoUpdateInstall") {
        didSet { UserDefaults.standard.set(autoInstall, forKey: "autoUpdateInstall") }
    }
    private var loop: Task<Void, Never>?

    var isAvailable: Bool { if case .available = state { return true } else { return false } }

    /// Ishga tushgandan 30 s keyin va har 12 soatda tekshiradi.
    func startBackground() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            while !Task.isCancelled {
                if let self, self.autoCheck {
                    await self.check(silent: true)
                    // Siz ilovada ishlayotganda (oyna ochiq) o'zi yopilib qolmasin
                    if self.autoInstall, self.isAvailable, Installer.canSelfUpdate(),
                       !NSApp.windows.contains(where: { AppModels.isMainWindow($0) && $0.isVisible }) {
                        await self.install()
                    }
                }
                try? await Task.sleep(nanoseconds: 12 * 3_600_000_000_000)
            }
        }
    }

    func check(silent: Bool = false) async {
        if case .downloading = state { return }
        if state == .installing { return }
        if !silent { state = .checking }
        do {
            let r = try await ReleaseFetcher.latest()
            if VersionCompare.isNewer(r.version, than: UpdateConfig.currentVersion) {
                release = r
                state = .available(r.version)
            } else {
                release = nil
                state = .upToDate
            }
        } catch ReleaseFetcher.FetchError.http(404) {
            if silent { if !isAvailable { state = .idle } } else {
                state = .failed(T("Hali reliz yo'q yoki repo yopiq", "No release yet, or the repo is private",
                                  "Релизов пока нет или репозиторий закрыт"))
            }
        } catch {
            if silent { if !isAvailable { state = .idle } } else {
                state = .failed(T("Internetni tekshiring", "Check your internet connection", "Проверьте интернет"))
            }
        }
    }

    func install() async {
        guard let r = release else { return }
        guard Installer.canSelfUpdate() else {
            state = .failed(T("Max Clean'ni Applications papkasiga ko'chirib, o'sha yerdan oching",
                              "Move Max Clean to the Applications folder and open it from there",
                              "Переместите Max Clean в «Программы» и откройте оттуда"))
            return
        }
        state = .downloading(0)
        do {
            try FileManager.default.createDirectory(at: UpdateConfig.workDir, withIntermediateDirectories: true)
            let dest = UpdateConfig.workDir.appendingPathComponent("MaxClean-\(r.version).dmg")
            let dl = DownloadTask(destination: dest) { p in
                Task { @MainActor [weak self] in
                    if case .downloading = self?.state { self?.state = .downloading(p) }
                }
            }
            let dmg = try await dl.run(r.dmgURL)
            state = .installing
            let version = r.version
            let staged = try await Task.detached { try Installer.stage(dmg: dmg, expectedVersion: version) }.value
            try? FileManager.default.removeItem(at: dmg)
            try Installer.replaceAndRelaunch(with: staged)
        } catch Installer.InstallError.wrongApp {
            state = .failed(T("Yuklangan fayl Max Clean emas — o'rnatilmadi", "The download isn't Max Clean — not installed",
                              "Загруженный файл — не Max Clean, установка отменена"))
        } catch {
            state = .failed(T("Yangilab bo'lmadi: \(error.localizedDescription)", "Update failed: \(error.localizedDescription)",
                              "Не удалось обновить: \(error.localizedDescription)"))
        }
    }
}

/// Sozlamalar va bosh sahifa uchun yangilanish kartasi.
struct UpdateCard: View {
    @EnvironmentObject var updater: AutoUpdater
    var compact = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.title2).foregroundStyle(Theme.accentGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(T("Joriy versiya: \(UpdateConfig.currentVersion)", "Current version: \(UpdateConfig.currentVersion)",
                               "Текущая версия: \(UpdateConfig.currentVersion)"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    action
                }
                if case .downloading(let p) = updater.state {
                    ProgressView(value: p).tint(Theme.accent)
                }
                if !compact, let r = updater.release, updater.isAvailable, !r.notes.isEmpty {
                    Text(r.notes).font(.caption).foregroundStyle(.secondary).lineLimit(6)
                }
                if !compact {
                    Toggle(T("Yangilanishlarni avtomatik tekshirish", "Check for updates automatically",
                             "Автоматически проверять обновления"), isOn: $updater.autoCheck).toggleStyle(.switch)
                    Toggle(T("Topilsa — o'zi o'rnatsin", "Install updates automatically", "Устанавливать автоматически"),
                           isOn: $updater.autoInstall).toggleStyle(.switch).disabled(!updater.autoCheck)
                }
            }
        }
    }

    var title: String {
        switch updater.state {
        case .idle: return T("Yangilanish", "Updates", "Обновления")
        case .checking: return T("Tekshirilmoqda…", "Checking…", "Проверка…")
        case .upToDate: return T("Eng yangi versiya o'rnatilgan", "You're up to date", "Установлена последняя версия")
        case .available(let v): return T("Yangi versiya: \(v)", "New version: \(v)", "Новая версия: \(v)")
        case .downloading(let p): return T("Yuklanmoqda… \(Int(p * 100))%", "Downloading… \(Int(p * 100))%", "Загрузка… \(Int(p * 100))%")
        case .installing: return T("O'rnatilmoqda — ilova qayta ochiladi", "Installing — the app will relaunch", "Установка — приложение перезапустится")
        case .failed(let m): return m
        }
    }

    @ViewBuilder var action: some View {
        switch updater.state {
        case .available:
            Button(T("Yangilash", "Update", "Обновить")) { Task { await updater.install() } }
                .buttonStyle(GlowButtonStyle())
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        default:
            Button(T("Tekshirish", "Check", "Проверить")) { Task { await updater.check() } }
                .buttonStyle(GhostButtonStyle())
        }
    }
}
